// idr.facts:effects: what running some code may do.
export module idr.facts:effects;

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
};

} // namespace idr::facts
