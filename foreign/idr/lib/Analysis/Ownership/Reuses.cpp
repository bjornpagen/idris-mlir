// Reset/reuse insertion's decisions, on functional code whose match
// regions end in their join point.
//
// In a case region of a match on a box that is dead after the match, the
// box's constructor is known, so is its cell's size. whereDies finds where
// the box dies on each path of the region: after its last use there, or,
// when that use is a match, inside each of that match's regions. A last
// use that consumes the box (a call, a constructor) is where it dies, and
// its cell goes with it: nothing is taken on that path. Elsewhere `fits`
// looks ahead on the same path for the first constructor of a box with a
// cell of the same size, going into the regions of the matches it meets,
// and builds it in the dead box's cell instead: idr.take where the box dies,
// idr.reuse for the constructor. idr-rc-place makes both; placement then
// drops the token on the paths that do not reuse it. Inner matches are
// done first, so that their scrutinees, which die later, get the
// constructors built after them.
//
// A box that is static, borrowed or built in the stack frame
// (`idr.stack`) is left alone: its cell is not the program's to reuse.
//
// Each decision is taken on the function as the takes before it leave it:
// a take gives the reads of the box's fields after it fields of its own,
// and a box that is then only read, which a later decision may take apart,
// is that field. Nothing is rewritten here, so the moves are kept beside
// the function: which uses each take will have moved, and to which of its
// fields.
#include "idr/Analysis/Ownership.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Ownership.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Threading.h"
#include "llvm/ADT/Sequence.h"

using namespace mlir;
using namespace idr::ownership;

namespace idr {

namespace {

using Site = Reuses::Site;

// A value as the rewrite will find it: an original value, or, when `value`
// is null, the field `virt` names of an earlier site's take.
struct Held {
  Value value;
  unsigned virt = 0;
};

// A field of a site's take: its type, and the uses the take gives it.
struct Virtual {
  unsigned site, field;
  Type type;
  SmallVector<OpOperand *> uses;
};

class Decider {
public:
  Decider(FuncOp fn, SymbolTable &symbols, const Layouts &layouts,
          IdrDialect::StackAttrHelper stack)
      : fn(fn), symbols(symbols), layouts(layouts), stack(stack) {}

  SmallVector<Site> run() {
    SmallVector<MatchOp> matches;
    fn.walk([&](MatchOp match) { matches.push_back(match); });
    for (MatchOp match : matches) {
      Value box = match.getScrutinee();
      if (!isa<BoxType>(unrestricted(box.getType())) || !reusable(Held{box}) ||
          usedAfter(box, match))
        continue;
      DataOp data = lookupData(symbols, box.getType());
      for (auto [index, name] : llvm::enumerate(match.getCases().getAsRange<FlatSymbolRefAttr>())) {
        CtorOp ctor = data ? lookupCtor(data, name.getValue()) : CtorOp();
        Region &region = match.getCaseRegion(static_cast<unsigned>(index));
        if (ctor && !region.empty())
          dies(Held{box}, ctor, region.front(), &region.front());
      }
    }
    readBoxes();
    return std::move(sites);
  }

private:
  // A box that no match takes apart, whose every use reads a field of one
  // constructor: a read directly in a block proves the constructor from
  // there on, so the box dies in that block as a matched one does. The
  // boxes are found once the matched boxes are decided, the fields their
  // takes give among them, in the order a walk would meet them.
  void readBoxes() {
    unsigned matched = static_cast<unsigned>(sites.size());
    for (unsigned index = 0; index < matched; ++index)
      (sites[index].after ? takesAfter[sites[index].after] : takesAtStart[sites[index].block])
          .push_back(index);
    for (Block &block : fn.getBody())
      visit(block);
    for (auto [box, first] : boxes) {
      auto name = SymbolRefAttr::get(getSumName(typeOf(box)).getAttr(), {first.getCtorAttr()});
      if (CtorOp ctor = lookupCtor(symbols, name))
        dies(box, ctor, *first->getBlock(), nullptr);
    }
  }

  // Each value of `block` as a post-order walk meets it, a take's fields
  // where the take will go. Takes at one point come last-made first, as
  // each is made right at the point.
  void visit(Block &block) {
    SmallVector<unsigned> atStart = takesAtStart.lookup(&block);
    for (unsigned site : llvm::reverse(atStart))
      considerTake(site);
    for (Operation &op : block) {
      for (Region &region : op.getRegions())
        for (Block &inner : region)
          visit(inner);
      for (Value result : op.getResults())
        if (isa<BoxType>(unrestricted(result.getType())))
          consider(Held{result});
      SmallVector<unsigned> after = takesAfter.lookup(&op);
      for (unsigned site : llvm::reverse(after))
        considerTake(site);
    }
  }

  void considerTake(unsigned site) {
    for (unsigned field = 0, e = static_cast<unsigned>(sites[site].ctor.getFieldTypes().size());
         field < e; ++field)
      if (auto it = virtualOf.find({site, field}); it != virtualOf.end())
        consider(Held{nullptr, it->second});
  }

  void consider(Held box) {
    if (FieldOp first = onlyReads(typeOf(box), usesOf(box)); first && reusable(box))
      boxes.emplace_back(box, first);
  }

  Type typeOf(const Held &box) const {
    return box.value ? box.value.getType() : virtuals[box.virt].type;
  }

  SmallVector<OpOperand *> usesOf(const Held &box) const {
    if (!box.value)
      return virtuals[box.virt].uses;
    SmallVector<OpOperand *> uses;
    for (OpOperand &use : box.value.getUses())
      if (!moved.contains(&use))
        uses.push_back(&use);
    return uses;
  }

  // Whether `box` holds its own reference: not static, not a stack cell.
  // A take's field always does. Borrow inference keeps a parameter that is
  // taken apart owned.
  bool reusable(const Held &box) {
    for (Value value = box.value; value; value = readFrom(value)) {
      if (isStatic(value))
        return false;
      if (auto con = value.getDefiningOp<ConOp>(); con && stack.isAttrPresent(con))
        return false;
    }
    return true;
  }

  // Where `box`, built by `ctor`, whose fields `fields` binds (when a match
  // region does), dies on each path of `block`, the first constructor after
  // that point whose cell fits gets the box's cell.
  void dies(Held box, CtorOp ctor, Block &block, Block *fields) {
    SmallVector<OpOperand *> uses = usesOf(box);
    unsigned size = layouts.box(ctor).size;
    whereDies(uses, block, /*graded=*/nullptr, [&](Block &where, Block::iterator at) {
      SmallVector<ConOp> found;
      if (fits(size, where, at, found))
        record(box, ctor, where, at, fields, std::move(found), uses);
    });
  }

  // The first constructor on each path from `at` whose cell fits, or
  // false when there is none. The body of a loop over an array runs once
  // per element, so a constructor in it cannot take the one cell. A
  // constructor an earlier take has is a reuse already, and passed over.
  bool fits(unsigned size, Block &block, Block::iterator at, SmallVectorImpl<ConOp> &found) {
    for (Operation &op : llvm::make_range(at, block.end())) {
      if (auto con = dyn_cast<ConOp>(op)) {
        if (!claimed.contains(con) && isa<BoxType>(unrestricted(con.getType())) &&
            !stack.isAttrPresent(con))
          if (CtorOp ctor = lookupCtor(symbols, con.getCtor());
              ctor && layouts.box(ctor).size == size) {
            found.push_back(con);
            return true;
          }
        continue;
      }
      if (op.getNumRegions() == 0 || isArrayLoop(&op))
        continue;
      bool any = false;
      for (Region &region : op.getRegions())
        if (!region.empty() && fits(size, region.front(), region.front().begin(), found))
          any = true;
      if (any)
        return true;
    }
    return false;
  }

  // A take of `box` at `at`, for the constructors `found`: the site, and
  // the uses of its fields from that point on, which it will move.
  void record(Held box, CtorOp ctor, Block &where, Block::iterator at, Block *fields,
              SmallVector<ConOp> found, ArrayRef<OpOperand *> uses) {
    auto index = static_cast<unsigned>(sites.size());
    Site site;
    site.box = box.value;
    if (!box.value) {
      site.from = virtuals[box.virt].site;
      site.field = virtuals[box.virt].field;
    }
    site.ctor = ctor;
    site.block = &where;
    site.after = at == where.begin() ? nullptr : &*std::prev(at);
    site.fields = fields;
    claimed.insert(found.begin(), found.end());
    site.cons = std::move(found);
    sites.push_back(std::move(site));
    Type boxType = typeOf(box);
    eachField(uses, ctor, fields, [&](Value field, unsigned number) {
      unsigned virt = virtualFor(index, number, fieldType(boxType, ctor.getFieldType(number)));
      for (OpOperand &use : field.getUses())
        if (!moved.contains(&use) && fromPoint(where, at, use)) {
          moved[&use] = virt;
          virtuals[virt].uses.push_back(&use);
        }
    });
  }

  unsigned virtualFor(unsigned site, unsigned field, Type type) {
    auto [it, fresh] = virtualOf.try_emplace({site, field}, static_cast<unsigned>(virtuals.size()));
    if (fresh)
      virtuals.push_back(Virtual{site, field, type, {}});
    return it->second;
  }

  FuncOp fn;
  SymbolTable &symbols;
  const Layouts &layouts;
  IdrDialect::StackAttrHelper stack;
  SmallVector<Site> sites;
  // The constructors a site builds in its cell.
  DenseSet<Operation *> claimed;
  // Every use a site's take will move, and the field it moves to.
  DenseMap<OpOperand *, unsigned> moved;
  SmallVector<Virtual> virtuals;
  DenseMap<std::pair<unsigned, unsigned>, unsigned> virtualOf;
  DenseMap<Operation *, SmallVector<unsigned>> takesAfter;
  DenseMap<Block *, SmallVector<unsigned>> takesAtStart;
  SmallVector<std::pair<Held, FieldOp>> boxes;
};

} // namespace

// Each function's sites depend on its body, the declarations and the
// layouts alone, so they are found in parallel, one slot per function.
Reuses::Reuses(Operation *module, AnalysisManager &am) {
  SymbolTable &symbols = am.getAnalysis<SymbolTable>();
  const Layouts &layouts = am.getAnalysis<Layouts>();
  if (failed(layouts.valid()))
    return;
  IdrDialect::StackAttrHelper stack(module->getContext());
  SmallVector<FuncOp> functions;
  for (FuncOp fn : cast<ModuleOp>(module).getOps<FuncOp>())
    if (!fn.isExternal())
      functions.push_back(fn);
  SmallVector<SmallVector<Site>> slots(functions.size());
  parallelForEach(module->getContext(), llvm::seq<size_t>(0, functions.size()), [&](size_t index) {
    slots[index] = Decider(functions[index], symbols, layouts, stack).run();
  });
  for (auto [fn, found] : llvm::zip_equal(functions, slots))
    if (!found.empty())
      sitesOf[fn] = std::move(found);
}

bool Reuses::isInvalidated(const AnalysisManager::PreservedAnalyses &pa) const {
  return !pa.isPreserved<Reuses>() || !pa.isPreserved<SymbolTable>() || !pa.isPreserved<Layouts>();
}

ArrayRef<Reuses::Site> Reuses::sites(FuncOp fn) const {
  auto it = sitesOf.find(fn);
  return it == sitesOf.end() ? ArrayRef<Site>() : ArrayRef<Site>(it->second);
}

} // namespace idr
