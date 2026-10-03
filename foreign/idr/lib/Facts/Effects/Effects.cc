// The members of Effects.
module idr.facts;

namespace idr::facts {

Effects Effects::all() { return {true, true, true}; }

bool Effects::none() const { return !io && !crash && !diverge; }

Effects &Effects::operator|=(const Effects &other) {
  io |= other.io;
  crash |= other.crash;
  diverge |= other.diverge;
  return *this;
}

} // namespace idr::facts
