// The members of Effects.
module idr.facts;

namespace idr::facts {

Effects Effects::all() { return {true, true, true}; }

bool Effects::none() const { return !io && !crash && !partial; }

Effects &Effects::operator|=(const Effects &other) {
  io |= other.io;
  crash |= other.crash;
  partial |= other.partial;
  return *this;
}

} // namespace idr::facts
