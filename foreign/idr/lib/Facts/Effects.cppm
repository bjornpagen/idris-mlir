// idr.facts:effects: what running some code may do.
export module idr.facts:effects;

export namespace idr::facts {

// What running some code may do besides computing its results and
// allocating them: perform IO (or anything at all), crash, or fail to
// return.
struct Effects {
  bool io = false;
  bool crash = false;
  bool partial = false;

  static Effects all();
  bool none() const;
  Effects &operator|=(const Effects &other);
};

} // namespace idr::facts
