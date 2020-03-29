import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:toast/toast.dart';
import 'package:image/image.dart' as img;
import 'package:mlkit/mlkit.dart';

class HomePage extends StatefulWidget{
  @override
  State<StatefulWidget> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>{

  CameraController controller;
  bool cameraReady = false;
  File selectedImageFile;
  List<CameraDescription> cameras;

  FirebaseModelInterpreter interpreter = FirebaseModelInterpreter.instance;
  FirebaseModelManager manager = FirebaseModelManager.instance;
  List<String> modelLabels = [];
  Map<String, double> predictions = Map<String, double>();

  int imageDim = 256;
  List<int> inputDims = [1, 256, 256, 3];
  List<int> outputDims = [1, 15];

  @override
  void initState(){
    super.initState();
    initCam();
    loadTFliteModel();
  }

  initCam() async{
    cameras = await availableCameras();
    if(cameras.length > 0){
      controller = CameraController(cameras[0], ResolutionPreset.medium);
      controller.initialize().then((_){
        setState(() {
          cameraReady = true;
        });
      });
    }
  }

  loadTFliteModel() async{
    try{
      manager.registerLocalModelSource(
        FirebaseLocalModelSource(
          assetFilePath: "assets/models/plant_ai_lite_model.tflite",
          modelName: "plant_ai_model"
        )
      );
      // 
      rootBundle.loadString('assets/models/labels_plant_ai.txt').then((string) {
        var _labels = string.split('\n');
        _labels.removeLast();
        modelLabels = _labels;
      });
      // 
    } catch (e){
      Toast.show(
        "$e",
        context,
        duration: Toast.LENGTH_SHORT,
        gravity:  Toast.BOTTOM
      );
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

  pickPhoto() async{
    var image = await ImagePicker.pickImage(source: ImageSource.gallery);
    if(image != null){
      setState(() {
        selectedImageFile = image;
      });
      predict(selectedImageFile);
    }
  }

  takePicture() async{
    final Directory extDir = await getApplicationDocumentsDirectory();
    final String dirPath = '${extDir.path}/Pictures/flutter_test';
    await Directory(dirPath).create(recursive: true);
    final String filePath = '$dirPath/${timestamp()}.jpg';

    if(controller.value.isTakingPicture){
      return null;
    }
    controller.takePicture(filePath).then((_){
      var pictureFile = File(filePath);
      predict(pictureFile);
    });
  }

  rotateCamera(){
  }

  predict(File imageFile) async{
    try{
      predictions = Map<String, double>();
      // 
      var bytes = await imageToByteListFloat(imageFile, imageDim);
      var results = await interpreter.run(
        localModelName: "plant_ai_model",
        inputOutputOptions: FirebaseModelInputOutputOptions(
          [
            FirebaseModelIOOption(FirebaseModelDataType.FLOAT32, inputDims)
          ],
          [
            FirebaseModelIOOption(FirebaseModelDataType.FLOAT32, outputDims)
          ]
        ),
        inputBytes: bytes
      );
      if(results != null && results.length > 0){
        for (var i = 0; i < results[0][0].length; i++) {
          if (results[0][0][i] > 0) {
            var confidenceLevel = results[0][0][i] / 2.55 * 100;
            if(confidenceLevel > 0){
              predictions[modelLabels[i]] = confidenceLevel;
            }
          }
        }
        // sort prdictions
        var predictionKeys = predictions.entries.toList();
        predictionKeys.sort((b,a)=>a.value.compareTo(b.value));
        predictions = Map<String, double>.fromEntries(predictionKeys);
        // 
        showAlertDialog();
        // 
      } else{
        showMessageAlert("Error", 'I am not sure I can find a plant image in the provided picture');
      }
    } catch (e) {
      showMessageAlert("Error", e.toString());
    }
  }

  Future<void> showAlertDialog() async {
    List<Widget> predictionWidget = [];
    // sort prdictions
    var predictionKeys = predictions.entries.toList();
    predictionKeys.sort((b,a)=>a.value.compareTo(b.value));
    predictions = Map<String, double>.fromEntries(predictionKeys);
    // 
    predictions.forEach((k, v){
      predictionWidget.add(
        Text("$k : ${v.round()} %")
      );
    });
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Predictions"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: predictionWidget,
            ),
          ),
          actions: <Widget>[
            FlatButton(
              child: Text('Ok'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> showMessageAlert(String title, String message) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            FlatButton(
              child: Text('Ok'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<Uint8List> imageToByteListFloat(File file, int _inputSize) async {
    var bytes = file.readAsBytesSync();
    var decoder = img.findDecoderForData(bytes);
    img.Image image = decoder.decodeImage(bytes);
    var convertedBytes = Float32List(1 * _inputSize * _inputSize * 3);
    var buffer = Float32List.view(convertedBytes.buffer);
    int pixelIndex = 0;
    for (var i = 0; i < _inputSize; i++) {
      for (var j = 0; j < _inputSize; j++) {
        var pixel = image.getPixel(i, j);
        buffer[pixelIndex] = ((pixel >> 16) & 0xFF) / 255;
        pixelIndex += 1;
        buffer[pixelIndex] = ((pixel >> 8) & 0xFF) / 255;
        pixelIndex += 1;
        buffer[pixelIndex] = ((pixel) & 0xFF) / 255;
        pixelIndex += 1;
      }
    }
    return convertedBytes.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Plant Disease Recognition"),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: Container(
                color: Colors.white,
                height: MediaQuery.of(context).size.height,
                child: 
                (cameraReady && selectedImageFile == null)
                ? AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: CameraPreview(controller),
                  )
                : (selectedImageFile == null)
                  ? SizedBox()
                  : Image.file(
                      selectedImageFile,
                      fit: BoxFit.cover,
                    )
              ),
            ),
            Positioned(
              left: 0,
              bottom: 20.0,
              child: RaisedButton(
                onPressed: (){
                  pickPhoto();
                },
                child: Icon(
                  Icons.photo,
                  color: Colors.white,
                  size: 25,
                ),
                padding: const EdgeInsets.all(10),
                color: Colors.red,
                shape: CircleBorder()
              ),
            ),
            Positioned(
              left: 50,
              right: 50,
              bottom: 20.0,
              child: RaisedButton(
                onPressed: (){
                  takePicture();
                },
                child: Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: 30,
                ),
                padding: const EdgeInsets.all(20),
                color: Colors.red,
                shape: CircleBorder()
              ),
            ),
            Positioned(
              right: 10,
              bottom: 20.0,
              child: RaisedButton(
                onPressed: (){
                  rotateCamera();
                },
                child: Icon(
                  Icons.switch_camera,
                  color: Colors.white,
                  size: 25,
                ),
                padding: const EdgeInsets.all(10),
                color: Colors.red,
                shape: CircleBorder()
              ),
            )
          ],
        ),
      ),
    );
  }
  
}