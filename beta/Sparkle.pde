// based on "Embers": https://www.openprocessing.org/sketch/513366

class Sparkle {
  PVector loc, vel;
  float life;
  color c;

  Sparkle(PVector _loc, PVector _vel, color _c) {
    this.loc = new PVector(_loc.x, _loc.y, _loc.z);
    this.vel = new PVector(_vel.x, _vel.y, _vel.z);
    this.life = 1.0;
    this.c = _c;
  }

  void show() {
    stroke(color(red(c)+200*chorus, green(c), blue(c)+200*(1-chorus)),
           255 * pow(this.life, 2)); // diminish alpha with life^2
    strokeWeight(10);
    float w = 2*0.5f/zoomF; // coefficient to make the tail of spakles long
    line(loc.x, loc.y, loc.z, 
      loc.x + w*vel.x, loc.y + w*vel.y, loc.z + w*vel.z);

    this.loc.add(this.vel);
    this.vel.div(1.1);
    this.life -= 0.01; // decide diminishing speed of the sparkles
  }
}
