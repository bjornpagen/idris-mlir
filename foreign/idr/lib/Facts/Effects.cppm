// idr.facts:effects: what running some code may do. The working form is three
// flags; `idr.effects` stores the same fact as the dialect's `Effect` bits,
// and `bits` / `from` are that form.
export module idr.facts:effects;

import idr.dialect;

using namespace idr;

export namespace idr::facts {

// What running some code may do besides computing its results and
// allocating them: perform IO (or anything at all), crash, or fail to
// return.
struct Effects {
  bool io = false;
  bool crash = false;
  bool diverge = false;

  static Effects all() { return {true, true, true}; }
  bool none() const { return !io && !crash && !diverge; }
  Effects &operator|=(const Effects &other) {
    io |= other.io;
    crash |= other.crash;
    diverge |= other.diverge;
    return *this;
  }

  // `idr.effects`'s bits.
  Effect bits() const {
    Effect stored = Effect::none;
    if (io)
      stored = stored | Effect::io;
    if (crash)
      stored = stored | Effect::crash;
    if (diverge)
      stored = stored | Effect::diverge;
    return stored;
  }

  static Effects from(Effect stored) {
    return {bitEnumContainsAny(stored, Effect::io), bitEnumContainsAny(stored, Effect::crash),
            bitEnumContainsAny(stored, Effect::diverge)};
  }
};

} // namespace idr::facts
