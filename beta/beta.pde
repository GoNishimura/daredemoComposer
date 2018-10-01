import SimpleOpenNI.*;
import oscP5.*;
import netP5.*;

SimpleOpenNI context;
NetAddress myRemoteLocation;
float        zoomF = 0.5f; // 0.3f: z=(rHandPos.z+1000)/(1000*0.35f/zoomF) z+2000for0.5f
float        rotX = radians(180);  // by default rotate the hole scene 180deg around the x-axis, 
// the data from openni comes upside down
float        rotY = radians(0);
boolean      autoCalib=true;

PVector      bodyCenter = new PVector();
PVector      bodyDir = new PVector();
PVector      com = new PVector();                                   
PVector      com2d = new PVector();                                   
color[]      userClr = new color[]{ 
  color(147, 142, 219), 
  color(27, 158, 119), 
  color(217, 95, 2), 
  color(231, 41, 138), 
  color(102, 166, 30), 
  color(230, 171, 2), 
};

ArrayList<PVector> rHandHist = new ArrayList();
ArrayList<PVector> lHandHist = new ArrayList();
int          num_path = 20; // number of paths of both hands
int          path_len = 30; // length of each path
int[]        path_dif = new int[num_path]; // difference of each path
color[]      path_clr = new color[num_path]; // color for each path
PVector      rHandSpd = new PVector();
PVector      lHandSpd = new PVector();
ArrayList<Sparkle> spks = new ArrayList();
ArrayList<Sparkle> dead = new ArrayList();

// if zoom is different, change those numbers
float lenHandHeight = 1000; // -340 ~ 500 in 0.4f, -500 ~ 500 in 0.5f // -200, 800
float minHandHeight = 200;
float lenShoulder = 280; // 280 in 0.4f, 280 in 0.5f
float maxSpd = 90; // 120 in 0.4f, 100 in 0.5f
float maxLen = 1300; // 1000 in o.5f, 1300 in 0.5f
float flt = 0.6; // coefficient of importance of now in low pass filter for handSpd

// OSC msg from 0 to 1
float autoFilter = 0.5; // distance between hands. Updated in betweenHands()
float chorus     = 0.5; // height of the left hand. Updated in updateHand()
float inTheAir   = 0.5; // direction of the body. Updated in dirBody(). 0 when facing left
float strgSnp   = 0.5; // speed of the right hand. Updated in updateHand()


void setup() {
  size(1024, 768, P3D);
  myRemoteLocation = new NetAddress("127.0.0.1", 57137);
  context = new SimpleOpenNI(this);
  if (context.isInit() == false) {
    println("Can't init SimpleOpenNI, maybe the camera is not connected!"); 
    exit();
    return;
  }
  context.setMirror(false); // disable mirror
  context.enableDepth(); // enable depthMap generation 
  context.enableUser(); // enable skeleton generation for all joints

  stroke(255, 255, 255);
  smooth();  
  perspective(radians(45), float(width)/float(height), 10, 150000);
  blendMode(ADD);
  for (int i = 0; i < num_path; i++) {
    path_dif[i] = (int)random(-2*num_path, 2*num_path); // initialize dif
    float a = ((float)path_dif[i]/(2*num_path)+1)/2; // take 0 ~ 1
    float b = 4*a*(1-a); // logistic map. take 0 ~ 1
    float c = 4*b*(1-b);
    path_clr[i] = color(255*a, 255*b, 255*c); // initialize clr
  }
}

void draw() {
  context.update(); // update the cam
  background(23, 24, 7);

  // set the scene pos
  translate(width/2, height/2, 0);
  rotateX(rotX);
  rotateY(rotY);
  scale(zoomF);
  translate(0, 0, -1000);  // set the rotation center of the scene 1000 infront of the cam

  int[]   depthMap = context.depthMap();
  int[]   userMap  = context.userMap();
  int     steps    = 10;  // to speed up the drawing, draw every third point
  int     index;
  PVector realWorldPoint;

  //textSize(30);
  //fill(255);
  //text("Hello world!", 100, 100);

  // draw human
  for (int y = 0; y < context.depthHeight(); y += steps) {
    for (int x = 0; x < context.depthWidth(); x += steps) {
      index = x + y * context.depthWidth();
      if (depthMap[index] > 0) { 
        // draw the projected point
        realWorldPoint = context.depthMapRealWorld()[index];
        if (userMap[index] != 0) {
          color usrClr = userClr[ (userMap[index] - 1) % userClr.length ];
          stroke(color(red(usrClr)*2*inTheAir, green(usrClr), blue(usrClr)*2*(1-inTheAir)));
          strokeWeight(steps*(index%25)/25);
          line(realWorldPoint.x, realWorldPoint.y, realWorldPoint.z, 
            realWorldPoint.x, realWorldPoint.y+steps, realWorldPoint.z);
        }
      }
    }
  } // draw human

  // draw the skeleton if it's available
  int[] userList = context.getUsers();
  for (int i = 0; i < userList.length; i++) {
    if (context.isTrackingSkeleton(userList[i])) {
      updateHand(userList[i]);
      if (rHandHist.size() > 2) println(rHandHist.get(rHandHist.size()-1), rHandHist.get(rHandHist.size()-2), rHandSpd);
      for (int j=0; j < num_path; j++) drawPath(path_clr[j], path_dif[j]);
      updateSparkles();
      betweenHands(); // calculate distance and draw between hands, update autoFilter
      dirBody(userList[i]); // decide the direction of the body
      sendOsc();
    }
  }
} // draw()

// update stats of hands
void updateHand(int userId) {
  PVector rHandPos = new PVector();
  PVector lHandPos = new PVector();
  float confidence; // returns 1 when tracking

  // get points of both hands in the vars of PVector
  confidence = context.getJointPositionSkeleton(userId, SimpleOpenNI.SKEL_RIGHT_HAND, rHandPos);
  confidence = context.getJointPositionSkeleton(userId, SimpleOpenNI.SKEL_LEFT_HAND, lHandPos);

  if (rHandHist.size() >= path_len) rHandHist.remove(0); // restrict size
  if (lHandHist.size() >= path_len) lHandHist.remove(0);
  rHandHist.add(rHandPos); // save points
  lHandHist.add(lHandPos);
  if (rHandHist.size() > 2) {
    PVector rSpdNow = PVector.sub(rHandHist.get(rHandHist.size()-1), rHandHist.get(rHandHist.size()-2));
    PVector lSpdNow = PVector.sub(lHandHist.get(rHandHist.size()-1), lHandHist.get(rHandHist.size()-2));
    PVector rSpdOld = PVector.sub(rHandHist.get(rHandHist.size()-2), rHandHist.get(rHandHist.size()-3));
    PVector lSpdOld = PVector.sub(lHandHist.get(rHandHist.size()-2), lHandHist.get(rHandHist.size()-3));
    rHandSpd = PVector.add(rSpdNow.mult(flt), rSpdOld.mult(1-flt));
    lHandSpd = PVector.add(lSpdNow.mult(flt), lSpdOld.mult(1-flt));
  }

  chorus = (float)(rHandHist.get(rHandHist.size()-1).y+minHandHeight-100)/lenHandHeight;
  //textSize(20);
  //fill(255);
  //text(rHandHist.get(rHandHist.size()-1).y, 30, 30);
  //text(chorus, 30, 60);
  //fill(255*chorus, 0, 255*(1-chorus));
  //noStroke();
  //ellipse(-100, -100, 30, 30);

  strgSnp = (float)lHandSpd.mag()/maxSpd;
  //textSize(30);
  //fill(255);
  //text(rHandSpd.mag(), 30, 30);
  //if (strgSnp > 0.8) fill(255*strgSnp, 0, 255*(1-strgSnp));
  //noStroke();
  //ellipse(-100, -100, 30, 30);
} // updateHand()

// draw path of the hands
void drawPath(color c, int d) {
  if (rHandHist.size() > 2) {
    strokeWeight(10);
    for (int i=0; i <= rHandHist.size()-2; i++) {
      float brgtns = (float)i/(rHandHist.size()-2);
      stroke(color(red(c)+255*chorus, green(c), blue(c)+255*(1-chorus)), 255*brgtns);

      line(rHandHist.get(i).x+d, rHandHist.get(i).y+d, rHandHist.get(i).z+d, 
        rHandHist.get(i+1).x+d, rHandHist.get(i+1).y+d, rHandHist.get(i+1).z+d);
      line(lHandHist.get(i).x+d, lHandHist.get(i).y+d, lHandHist.get(i).z+d, 
        lHandHist.get(i+1).x+d, lHandHist.get(i+1).y+d, lHandHist.get(i+1).z+d);
    }
  }
} // drawPath()

// update sparkles in a function
void updateSparkles() {
  if (rHandHist.size() > 10) {
    // controls how many sparkles added in a frame
    spks.add(new Sparkle(rHandHist.get(rHandHist.size()-1), rHandSpd, path_clr[frameCount%num_path]));
    spks.add(new Sparkle(lHandHist.get(lHandHist.size()-1), lHandSpd, path_clr[frameCount%num_path]));
    spks.add(new Sparkle(rHandHist.get(rHandHist.size()-5), rHandSpd, path_clr[(frameCount-4)%num_path]));
    spks.add(new Sparkle(lHandHist.get(lHandHist.size()-5), lHandSpd, path_clr[(frameCount-4)%num_path]));
    spks.add(new Sparkle(rHandHist.get(rHandHist.size()-10), rHandSpd, path_clr[(frameCount-9)%num_path]));
    spks.add(new Sparkle(lHandHist.get(lHandHist.size()-10), lHandSpd, path_clr[(frameCount-9)%num_path]));

    // showing and removig
    for (int i = 0; i < spks.size(); i++) {
      Sparkle sp = spks.get(i);
      sp.show();
      if (sp.life <= 0) spks.remove(i);
    }
  }
} // updateSparkles()

// calculate distance and draw between hands, update autoFilter
void betweenHands() {
  int len = rHandHist.size();
  float dist = PVector.dist(rHandHist.get(len-1), lHandHist.get(len-1));
  autoFilter = (float)dist/maxLen;
  PVector mid = PVector.div(PVector.add(rHandHist.get(len-1), lHandHist.get(len-1)),2);

  strokeWeight(20/(autoFilter+1));
  stroke(147*2*(autoFilter-0.3), 142, 219*2*(1-(autoFilter-0.3)), 255*(1-strgSnp));
  // right to mid
  line(rHandHist.get(len-1).x, rHandHist.get(len-1).y, rHandHist.get(len-1).z, 
    mid.x, mid.y-((zoomF/0.4f)*20/autoFilter), mid.z);
  line(rHandHist.get(len-1).x, rHandHist.get(len-1).y, rHandHist.get(len-1).z, 
    mid.x, mid.y+((zoomF/0.4f)*20/autoFilter), mid.z);
  line(rHandHist.get(len-1).x, rHandHist.get(len-1).y, rHandHist.get(len-1).z, 
    mid.x, mid.y, mid.z-((zoomF/0.4f)*20/autoFilter));
  line(rHandHist.get(len-1).x, rHandHist.get(len-1).y, rHandHist.get(len-1).z, 
    mid.x, mid.y, mid.z+((zoomF/0.4f)*20/autoFilter));
  
  // mid to left
  line(mid.x, mid.y-((zoomF/0.4f)*20/autoFilter), mid.z, 
    lHandHist.get(len-1).x, lHandHist.get(len-1).y, lHandHist.get(len-1).z);
  line(mid.x, mid.y+((zoomF/0.4f)*20/autoFilter), mid.z, 
    lHandHist.get(len-1).x, lHandHist.get(len-1).y, lHandHist.get(len-1).z);
  line(mid.x, mid.y, mid.z-((zoomF/0.4f)*20/autoFilter), 
    lHandHist.get(len-1).x, lHandHist.get(len-1).y, lHandHist.get(len-1).z);
  line(mid.x, mid.y, mid.z+((zoomF/0.4f)*20/autoFilter), 
    lHandHist.get(len-1).x, lHandHist.get(len-1).y, lHandHist.get(len-1).z);

  //textSize(30);
  //fill(255);
  //text(dist, 30, 30);
  //text(autoFilter, 30, 60);
  //fill(255*autoFilter, 0, 255*(1-autoFilter));
  //noStroke();
  //ellipse(-100, -100, 30, 30);
} // betweenHands()

// decide the direction of the body
void dirBody(int userId) {
  PVector jointL = new PVector();
  PVector jointH = new PVector();
  PVector jointR = new PVector();
  float  confidence;

  confidence = context.getJointPositionSkeleton(userId, SimpleOpenNI.SKEL_LEFT_SHOULDER, jointL);
  confidence = context.getJointPositionSkeleton(userId, SimpleOpenNI.SKEL_HEAD, jointH);
  confidence = context.getJointPositionSkeleton(userId, SimpleOpenNI.SKEL_RIGHT_SHOULDER, jointR);

  inTheAir = (jointL.z-jointR.z)/lenShoulder; // left: -1, right: 1
  inTheAir = (float)(inTheAir+1)/2; // left: 0, right: 1

  //textSize(20);
  //fill(255);
  //text(jointL.z, 30, 50);
  //text(jointR.z, 30, 80);
  //text(jointL.z- jointR.z, 30, 110);
  //fill(255*inTheAir, 0, 255*(1-inTheAir));
  //noStroke();
  //ellipse(-100, -100, 30, 30);
} // dirBody()

// send OSC message to each channel
void sendOsc() {
  OscMessage msg = new OscMessage("/ch1"); // distance of hands
  msg.add(0); // bank = 0 for Beat Mosaic
  if (autoFilter < 0.3) msg.add(1);
  else msg.add(0);
  OscP5.flush(msg, myRemoteLocation);
  
  OscMessage msg0 = new OscMessage("/ch1"); // distance of hands
  msg0.add(1); // bank = 1 for Crashing Wave
  if (autoFilter > 0.8) msg0.add(1);
  else msg0.add(0);
  OscP5.flush(msg0, myRemoteLocation);

  OscMessage msg2 = new OscMessage("/ch2"); // height of the left hand
  msg2.add(0); // bank = 0 for Warning
  msg2.add(2*(chorus-0.5));
  OscP5.flush(msg2, myRemoteLocation);
  
  OscMessage msg21 = new OscMessage("/ch2"); // height of the left hand
  msg21.add(1); // bank = 1 for Yo Man!
  msg21.add(2*(0.6-chorus));
  OscP5.flush(msg21, myRemoteLocation);

  OscMessage msg3 = new OscMessage("/ch3"); // dir of the body
  msg3.add(0); // bank = 0
  if (inTheAir > 0.7 || inTheAir < 0.3) msg3.add(1);
  else msg3.add(0);
  OscP5.flush(msg3, myRemoteLocation);

  if (strgSnp > 0.7 || strgSnp < 0.2) { // speed of the right hand
    OscMessage msg4 = new OscMessage("/ch4");
    msg4.add(0); // bank = 0
    if (strgSnp > 0.7) msg4.add(1);
    else msg4.add(0);
    OscP5.flush(msg4, myRemoteLocation);
  }
} // sendOsc()


// -----------------------------------------------------------------
// SimpleOpenNI user events

void onNewUser(SimpleOpenNI curContext, int userId) {
  println("onNewUser - userId: " + userId);
  println("\tstart tracking skeleton");
  context.startTrackingSkeleton(userId);
}

void onLostUser(SimpleOpenNI curContext, int userId) {
  println("onLostUser - userId: " + userId);
}

// -----------------------------------------------------------------

void keyPressed() {
  switch(key) {
    case ' ':
      context.setMirror(!context.mirror());
      break;
  }

  switch(keyCode) {
    case LEFT:
      rotY += 0.1f;
      break;
    case RIGHT:
      // zoom out
      rotY -= 0.1f;
      break;
    case UP:
      if (keyEvent.isShiftDown())
        zoomF += 0.01f;
      else
        rotX += 0.1f;
      break;
    case DOWN:
      if (keyEvent.isShiftDown()) {
        zoomF -= 0.01f;
        if (zoomF < 0.01) zoomF = 0.01;
      } 
      else rotX -= 0.1f;
      break;
  }
} // keyPressed()
