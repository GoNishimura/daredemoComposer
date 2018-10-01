# daredemoComposer
Using Kinect V1, Ableton Live, Processing, (and Myo), you can make effects to the music played in the Ableton Live by moving your body

KinectとMyoからOSC通信でAbleton Liveにデータを送り、再生中の音楽にエフェクトをかけつつ、ProcessingではKinectからの映像に処理をかけたものを表示します。betaにはKinectと映像の処理のためのProcessingファイルが、myoOSCはMyoから送られたデータをMaxで受け取ったものを、OSCでProcessingからAbletonに渡すものになっています。
