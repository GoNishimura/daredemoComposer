import oscP5.*;
import netP5.*;

OscP5 oscP5;
NetAddress myRemoteLocation;
boolean event_captured = false; // OSC message ever received
float[] emg = new float[8]; // 8ch EMG
String pose = new String(); // pose: bank 0 for default, 1 for fist, 2 for fingersSpread
float sum = 0;
float thresh = 1.5;

void setup() {
  background(127);
  size(400, 400);
  frameRate(25);
  oscP5 = new OscP5(this, 12002); // receive port
  myRemoteLocation = new NetAddress("127.0.0.1", 57137); // addr and port to send
}

void draw() {
  background(127);
  fill(255);
  textSize(20);
  
  if (!event_captured) text("Execute this program before sending\nOSC.\nAfter sending OSC, click the\nwindow of the program and check\nconsole.", 20,20);
  else {
    text("emg[0]: " + emg[0], 0, 20);
    text("pose: " + pose, 0, 40);
    text("sum: "+sum, 0, 60);
  }
  
  if (event_captured) {
    OscMessage msg = new OscMessage("/ch5");
    if (match(pose, "fist") != null) {
      msg.add(0); // bank = 0 for Around the Head
      msg.add(1); // value = 1
      oscP5.send(msg, myRemoteLocation);
    }
    else if (match(pose, "fingersSpread") != null) {
      msg.add(1); // bank = 1 for Suitcase
      msg.add(1);
      oscP5.send(msg, myRemoteLocation);
    }
    else {
      msg.add(0);
      msg.add(0); // value = 0
      oscP5.send(msg, myRemoteLocation);
      
      OscMessage msg2 = new OscMessage("/ch5");
      msg2.add(1);
      msg2.add(0);
      oscP5.send(msg2, myRemoteLocation);
    }
    
    sum = 0;
    for (int i = 0; i < 8; i++) sum += abs(emg[i]);
    OscMessage msg3 = new OscMessage("/ch6");
    msg3.add(0); // bank = 0
    if (sum > thresh) msg3.add(1);
    else msg3.add(0);
    oscP5.send(msg3, myRemoteLocation);
  }
}

void oscEvent(OscMessage theOscMessage) {
  switch(theOscMessage.typetag()){
    case "ffffffff":
    for (int i = 0; i < 8; i++) emg[i] = theOscMessage.get(i).floatValue();
    printArray(emg);
    break;
    
    case "s":
    pose = theOscMessage.get(0).stringValue();
    println(pose);
    break;
    
    default: // if not floats or String
    println("Type tag:", theOscMessage.typetag());
    break;
  }
  event_captured = true;
}
