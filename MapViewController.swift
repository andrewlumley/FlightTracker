//
//  MapViewController.swift
//  FlightTracker
//
//  Created by Andrew Lumley on 2014-12-28.
//  Copyright (c) 2014 Andrew Lumley. All rights reserved.
//

import UIKit
import GLKit
import CoreMotion

class MapViewController: UIViewController, CLLocationManagerDelegate, GMSMapViewDelegate {
    
    @IBOutlet weak var mapView: GMSMapView!
    @IBOutlet weak var StartandStop: UIButton!
    @IBOutlet weak var navBar: UINavigationItem!
    
    lazy var altimeter :CMAltimeter = CMAltimeter()
    let locationManager = CLLocationManager()
    
    var latitudes: [CLLocationDegrees] = []
    var longditudes: [CLLocationDegrees] = []
    var coordinates: [CLLocationCoordinate2D] = []
    var finished = false
    var lastLocation: CLLocationCoordinate2D = CLLocationCoordinate2DMake(0.0000, 0.0000)
    
    var timer = NSTimer()
    var path = GMSMutablePath()
    var distance: Float = 0.0
    var groundspeed: Float = 0.0
    var Heading: Float = 0.0
    
    var offset: Float = 0.0
    
    var altitude: Float = 0.0 {
        didSet { updateViewWithNewAlt(meter: self.altitude) }
    }
    
    var maxAlt: Float = Float(Int.min)
    var minAlt: Float = Float(Int.max)
    
    func saveAltitudeMeters(){  // This method loads the intial user preferences if required
        if loadAltitudeMeters() == 0.0 {
            NSUserDefaults.standardUserDefaults().setDouble(3.28084, forKey: "altitudeMeters")
        }
        if loadASL() == 0.0 {
            NSUserDefaults.standardUserDefaults().setDouble(2.0, forKey: "altitudeASL")
        }
        if loadHeading() == 0.0 {
            NSUserDefaults.standardUserDefaults().setDouble(2.0, forKey: "trueHeading")
        }
    }
    
    func loadAltitudeMeters() -> Double? {
        return NSUserDefaults.standardUserDefaults().doubleForKey("altitudeMeters")
    }
    
    func loadASL() -> Double? {
        return NSUserDefaults.standardUserDefaults().doubleForKey("altitudeASL")
    }
    
    func loadHeading() -> Double? {
        return NSUserDefaults.standardUserDefaults().doubleForKey("trueHeading")
    }
    
    func startAltimeterUpdate() {  // Called to initiate altitude updates if device has a barometer, must continue in background state
        self.altimeter.startRelativeAltitudeUpdatesToQueue(NSOperationQueue.currentQueue(),
            withHandler: { (altdata:CMAltitudeData!, error:NSError!) -> Void in
                self.handleNewMeasure(pressureData: altdata)
        })
    }
    
    func handleNewMeasure(#pressureData: CMAltitudeData) {  //Records last altitude to array in appDelegate
        let appDelegate = (UIApplication.sharedApplication().delegate as AppDelegate)
        self.altitude = pressureData.relativeAltitude.floatValue
        appDelegate.altitudes.append(self.altitude*3.28084)
    }
    
    func updateViewWithNewAlt(#meter :Float) {  //Records max/min altitude
        let newAlt = meter - self.offset
        if newAlt > self.maxAlt {
            self.maxAlt = newAlt
        }
        if newAlt < self.minAlt {
            self.minAlt = newAlt
        }
    }

    func locationManager(manager: CLLocationManager!, didChangeAuthorizationStatus status: CLAuthorizationStatus) { //Begins location updates when access granted by user
        if status == .Authorized {
            locationManager.startUpdatingLocation()
            mapView.myLocationEnabled = true
            mapView.settings.myLocationButton = true
        }
    }
    
    func locationManager(manager: CLLocationManager!, didUpdateHeading newHeading: CLHeading!) {  //This thread provides the direction of the device, can be canceled when app is in background
        let appDelegate = (UIApplication.sharedApplication().delegate as AppDelegate)
        let HeadingThread = NSOperationQueue()
        HeadingThread.name = "Heading Update"
        HeadingThread.addOperationWithBlock() {
            if let heading = newHeading {
                if NSUserDefaults.standardUserDefaults().doubleForKey("trueHeading") == 1.0 {
                    self.Heading = Float(newHeading.trueHeading)
                }
                else {
                    self.Heading = Float(newHeading.magneticHeading)
                }
                println("Heading")
                println(self.Heading)
                println(HeadingThread.operations)
            }
        }
    }

    func locationManager(manager: CLLocationManager!, didUpdateLocations locations: [AnyObject]!) { // This thread provides all of the heavy lifting, critical that it continues even in background state.
        
        let MapThread = NSOperationQueue()
        MapThread.name = "Map Update"
        MapThread.addOperationWithBlock() {
        
            if self.StartandStop.titleLabel?.text == "Start Flight" || self.StartandStop.titleLabel?.text == "Démarrez" {
                if let location = locations.first as? CLLocation {
                    let lastLocation = locations.last as? CLLocation
                    var altitude = lastLocation?.altitude
                    self.mapView.camera = GMSCameraPosition(target: location.coordinate, zoom: 17, bearing: 0, viewingAngle: 0)
                    //locationManager.stopUpdatingLocation()
                }
            }
            
            if self.StartandStop.titleLabel?.text == "Stop Flight" || self.StartandStop.titleLabel?.text == "Arrêtez" {
                if let mylocation = self.mapView.myLocation as CLLocation? {
                    let appDelegate = (UIApplication.sharedApplication().delegate as AppDelegate)
                    if CMAltimeter.isRelativeAltitudeAvailable() { // If barometer available, updates altitude
                        println("Check")
                        appDelegate.maxAltitude = NSString(format: "%.01f", self.maxAlt*3.28084) + " Ft"
                        //appDelegate.altitudes.append(self.altitude*3.28084)
                    }
                    else {
                        let relativeAlt = (self.mapView.myLocation as CLLocation).altitude - appDelegate.elevation // Provides altitude to devices without barometer
                        appDelegate.altitudes.append(Float(relativeAlt)*3.28084)
                        if Float(relativeAlt)*3.28084 > self.maxAlt {
                            self.maxAlt = Float(relativeAlt)*3.28084
                            appDelegate.maxAltitude = NSString(format: "%.01f", Float(relativeAlt)*3.28084) + " Ft"
                        }
                    }
                    var lastDistance = self.Distance(self.lastLocation, Coordinate2: (self.mapView.myLocation as CLLocation).coordinate) //App determines distance traveled
                    self.distance += lastDistance
                    var lastSpeed = Float((self.mapView.myLocation as CLLocation).speed) // Speed is recorded
                    if lastSpeed < 0 {
                        appDelegate.groundspeeds.append(0.0)
                    }
                    else {
                        appDelegate.groundspeeds.append(lastSpeed)
                    }
                    if self.groundspeed > lastSpeed {
                        appDelegate.groundspeed = NSString(format: "%.01f", Float((self.mapView.myLocation as CLLocation).speed)*1.94384) + " Kts"
                    }
                    self.groundspeed = lastSpeed
                    appDelegate.distance = NSString(format: "%.01f", self.distance/1.852) + " Nm"
                    println(self.distance)
                    self.path.addCoordinate(self.mapView.myLocation.coordinate)
                    //println(mylocation.coordinate.latitude) //
                    //println(mylocation.coordinate.longitude) //
                    self.latitudes.append((self.mapView.myLocation as CLLocation).coordinate.latitude)
                    self.longditudes.append((self.mapView.myLocation as CLLocation).coordinate.longitude)
                    GMSPolyline(path: self.path).map = self.mapView
                    self.mapView.camera = GMSCameraPosition(target: self.mapView.myLocation.coordinate as CLLocationCoordinate2D, zoom: 17, bearing: 0, viewingAngle: 0) // Map camera updated
                    self.lastLocation = (self.mapView.myLocation as CLLocation).coordinate
                }
            }
        }
    }
    
    func locationManager(manager: CLLocationManager!, didUpdateToLocation newLocation: CLLocation!, fromLocation oldLocation: CLLocation!) {
        var alt = newLocation.altitude
        manager.stopUpdatingLocation()
    }
    
    
    func Distance(Coordinate1: CLLocationCoordinate2D, Coordinate2: CLLocationCoordinate2D) -> Float { // Computes distance travelled
        var R: Float = 6371.0;
        var φ1 = GLKMathDegreesToRadians(Float(Coordinate1.latitude))
        var φ2 = GLKMathDegreesToRadians(Float(Coordinate2.latitude))
        var Δφ = GLKMathDegreesToRadians(((Float(Coordinate2.latitude))-(Float(Coordinate1.latitude))))
        var Δλ = GLKMathDegreesToRadians(((Float(Coordinate2.longitude))-(Float(Coordinate1.longitude))))
        
        var a = sin(Δφ/2) * sin(Δφ/2) +
            cos(φ1) * cos(φ2) *
            sin(Δλ/2) * sin(Δλ/2)
        var c = 2 * atan2(sqrt(a), sqrt(1-a))
        
        return R*c
    }

    
    func screenShot() { // Prepares view for final screenshot
        mapView.padding = UIEdgeInsetsMake(0.0, 0.0, 0.0, 0.0)
        mapView.settings.myLocationButton = false
        //mapView.myLocationEnabled = false
        if latitudes.count != 0 {
            latitudes.sort({ $0 < $1 })
            longditudes.sort({ $0 < $1 })
        }
        var length = longditudes[(longditudes.count)-1] - longditudes[0]
        var height = latitudes[(latitudes.count)-1] - latitudes[0]
        latitudes[0] -= abs(height*0.10)
        latitudes[(latitudes.count)-1] += abs(height*0.10)
        longditudes[0] -= abs(length*0.10)
        longditudes[(longditudes.count)-1] += abs(length*0.10)
        self.coordinates.append(CLLocationCoordinate2DMake(latitudes[0], longditudes[0]))
        self.coordinates.append(CLLocationCoordinate2DMake(latitudes[(latitudes.count)-1], longditudes[(longditudes.count)-1]))
        var bounds = GMSCoordinateBounds(coordinate: CLLocationCoordinate2DMake(latitudes[0], longditudes[0]), coordinate: CLLocationCoordinate2DMake(latitudes[(latitudes.count)-1], longditudes[(longditudes.count)-1]))
        var camera = mapView.cameraForBounds(bounds, insets:UIEdgeInsetsZero)
        mapView.animateToCameraPosition(camera)
        self.finished = true
    }
    
    func mapView(view: GMSMapView, idleAtCameraPosition position: GMSCameraPosition) { //Captures final map view
        if self.finished == true {
            UIGraphicsBeginImageContext(mapView.frame.size)
            mapView.layer.renderInContext(UIGraphicsGetCurrentContext())
            var image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            //UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            SaveFlight(image,path: self.path, pathBounds: self.coordinates)
            self.path.removeAllCoordinates()
            self.coordinates = []
            mapView.clear()
            //mapView.myLocationEnabled = true
            mapView.padding = UIEdgeInsetsMake(0.0, 0.0, 86.0, 0.0)
            mapView.settings.myLocationButton = true
            self.finished = false
            mapView.animateToCameraPosition(GMSCameraPosition(target: mapView.myLocation.coordinate, zoom: 17, bearing: 0, viewingAngle: 0))
            image = nil
        }
    }
    
    func SaveFlight(mapImage: UIImage, path: GMSMutablePath, pathBounds: [CLLocationCoordinate2D]) { // Saves session parameters at the end
        let save = FileSave()
        var mapData: NSData = UIImagePNGRepresentation(mapImage)
        var pathData: String = String(path.encodedPath())
        
        let manager = NSFileManager.defaultManager()
        let documentsPath = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)[0] as String
        var error : NSError?
        if let files = manager.contentsOfDirectoryAtPath(documentsPath, error: &error) {
            let count = files.count
            println(count)
            println("Now?")
            
            let appDelegate = (UIApplication.sharedApplication().delegate as AppDelegate)
            println(appDelegate.altitudes.description)
            FileSave.saveDataToDocumentsDirectory(mapData, path: "Map.png", subdirectory: "Flight"+String(count+1))
            FileSave.saveContentsOfStringToDocumentsDirectory(pathData, path:"MapPath.txt", subdirectory:"Flight"+String(count+1))
            FileSave.saveContentsOfStringToDocumentsDirectory(appDelegate.flightDate, path:"Date.txt", subdirectory:"Flight"+String(count+1))
            FileSave.saveContentsOfStringToDocumentsDirectory(appDelegate.distance, path:"Distance.txt", subdirectory:"Flight"+String(count+1))
            println(appDelegate.groundspeeds)
            FileSave.saveContentsOfStringToDocumentsDirectory((String(format:"%.01f", (maxElement(appDelegate.groundspeeds))*1.94384) + " Kts"), path:"Groundspeed.txt", subdirectory:"Flight"+String(count+1))
            FileSave.saveContentsOfStringToDocumentsDirectory(appDelegate.maxAltitude, path:"Altitude.txt", subdirectory:"Flight"+String(count+1))
            FileSave.saveContentsOfStringToDocumentsDirectory(NSString(format: "%.01f", appDelegate.elevation), path:"Elevation.txt", subdirectory:"Flight"+String(count+1))
            if appDelegate.altitudes.count == 1 {
                var altitudesArray: String = [0.0,appDelegate.altitudes[0]].description
                FileSave.saveContentsOfStringToDocumentsDirectory(altitudesArray, path:"Altitudes.txt", subdirectory:"Flight"+String(count+1))
            }
            else if appDelegate.altitudes.count > 1 && appDelegate.altitudes.count <= 20  {
                var altitudesArray: String = appDelegate.altitudes.description
                FileSave.saveContentsOfStringToDocumentsDirectory(altitudesArray, path:"Altitudes.txt", subdirectory:"Flight"+String(count+1))
            }
            else if appDelegate.altitudes.count > 20  {
                var buildArray: [Float] = []
                let test = (Float(appDelegate.altitudes.count))/20
                for index in (0...19) {
                    buildArray.append(appDelegate.altitudes[Int(floor(Float(index)*test))])
                }
                var altitudesArray = buildArray.description
                FileSave.saveContentsOfStringToDocumentsDirectory(altitudesArray, path:"Altitudes.txt", subdirectory:"Flight"+String(count+1))
            }
            if appDelegate.groundspeeds.count == 1 {
                var groundspeedsArray: String = [0.0,appDelegate.groundspeeds[0]].description
                FileSave.saveContentsOfStringToDocumentsDirectory(groundspeedsArray, path:"Groundspeeds.txt", subdirectory:"Flight"+String(count+1))
            }
            else if appDelegate.groundspeeds.count > 1 && appDelegate.groundspeeds.count <= 20  {
                var groundspeedsArray: String = appDelegate.groundspeeds.description
                FileSave.saveContentsOfStringToDocumentsDirectory(groundspeedsArray, path:"Groundspeeds.txt", subdirectory:"Flight"+String(count+1))
            }
            else if appDelegate.groundspeeds.count > 20  {
                var buildArray: [Float] = []
                let test = (Float(appDelegate.groundspeeds.count))/20
                for index in (0...19) {
                    buildArray.append(appDelegate.groundspeeds[Int(floor(Float(index)*test))])
                }
                var groundspeedsArray = buildArray.description
                FileSave.saveContentsOfStringToDocumentsDirectory(groundspeedsArray, path:"Groundspeeds.txt", subdirectory:"Flight"+String(count+1))
            }
            
            appDelegate.groundspeeds = [0.0]
            appDelegate.altitudes = [0.0]
            self.distance = 0.0
            self.groundspeed = 0.0
            mapView.settings.scrollGestures = true
            mapView.settings.zoomGestures = true
            mapView.settings.tiltGestures = true
            mapView.settings.rotateGestures = true
        } else {
            println("Could not get contents of directory: \(error?.localizedDescription)")
        }
    }
 
    @IBAction func StartandStop(sender: AnyObject) { // This IBAction is connected to the UIButton that starts and stops the app's tracking features
        
        if (StartandStop.titleLabel?.text == "Start Flight" || StartandStop.titleLabel?.text == "Démarrez") && mapView.myLocation != nil {
            timer.invalidate()
            StartandStop.setTitle(NSLocalizedString("STOP_FLIGHT", comment: "Stop Flight"), forState: UIControlState.Normal)
            StartandStop.setBackgroundImage(UIImage(named: "End"), forState: .Normal)
            if CMAltimeter.isRelativeAltitudeAvailable() {
                self.startAltimeterUpdate()
            }
            let date = NSDate()
            let dateFormatter = NSDateFormatter()
            dateFormatter.timeZone = NSTimeZone.systemTimeZone()
            dateFormatter.dateFormat = "yyyy/MM/dd"
            let appDelegate = (UIApplication.sharedApplication().delegate as AppDelegate)
            appDelegate.flightDate = dateFormatter.stringFromDate(date)
            println(appDelegate.flightDate)
            mapView.settings.scrollGestures = false
            mapView.settings.zoomGestures = false
            mapView.settings.tiltGestures = false
            mapView.settings.rotateGestures = false
            self.lastLocation = mapView.myLocation.coordinate
            appDelegate.elevation = mapView.myLocation.altitude
            println(appDelegate.elevation)
            println("meters")
            
            self.locationManager.distanceFilter = kCLDistanceFilterNone
            self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
            self.locationManager.startUpdatingLocation()
            self.locationManager.startUpdatingHeading()
        }
        else if StartandStop.titleLabel?.text == "Stop Flight" || StartandStop.titleLabel?.text == "Arrêtez" {
            StartandStop.setTitle(NSLocalizedString("START_FLIGHT",comment:"Start Flight"), forState: UIControlState.Normal)
            StartandStop.setBackgroundImage(UIImage(named: "Start"), forState: .Normal)
            if CMAltimeter.isRelativeAltitudeAvailable() {
                self.altimeter.stopRelativeAltitudeUpdates()
            }
            self.locationManager.stopUpdatingLocation()
            self.locationManager.stopUpdatingHeading()
            
            
            self.offset = self.altitude
            self.maxAlt = Float(Int.min)
            self.minAlt = Float(Int.max)
            self.altitude = 0.0
            self.Heading = 0.0
            
            if longditudes != [] && latitudes != [] {
                self.screenShot()
                self.latitudes = []
                self.longditudes = []
            }
            else {
                mapView.settings.scrollGestures = true
                mapView.settings.zoomGestures = true
                mapView.settings.tiltGestures = true
                mapView.settings.rotateGestures = true
            }
        }
    }
    
    @IBAction func settingsSelect(sender: AnyObject) {
        UIApplication.sharedApplication().openURL(NSURL(string: UIApplicationOpenSettingsURLString)!)
    }
    
    override func viewWillAppear(animated: Bool) {
        navBar.title = NSLocalizedString("START_A_FLIGHT",comment:"Start a Flight")
    }
    
    override func viewDidLoad() {
        saveAltitudeMeters()
        super.viewDidLoad()
        locationManager.delegate = self
        locationManager.requestAlwaysAuthorization()
        self.locationManager.distanceFilter = CLLocationDistance(1)
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
        self.locationManager.startUpdatingLocation()
        mapView.delegate = self
        mapView.padding = UIEdgeInsetsMake(0.0, 0.0, 86.0, 0.0)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}
