//
//  ViewController.swift
//  FairplayTestProj
//
//  Created by KingpiN on 22/11/21.
//
import UIKit
import AVKit
import AVFoundation

class ViewController: UIViewController, AVAssetResourceLoaderDelegate {
    
    let ACCESS_TOKEN: String = "YOUR_ACCESS_TOKEN_HERE"
    let RESOURCE_URL: String = "YOUR_SECURE_URL_HERE"
    let CUSTOM_SERIAL_QUEUE_LABEL: String = "co.ankit.queue"
    let CERTIFICATE_URL: String = "YOUR_CERTIFICATE_URL_HERE"
    let CKC_URL: String = "YOUR_CKC_URL_HERE"
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    @IBAction func playVideo(_ sender: UIButton) {
        let url = URL(string: RESOURCE_URL)!
        
        // Create the asset instance and the resource loader because we will be asked
        // for the license to playback DRM protected asset.
        let asset = AVURLAsset(url: url)
        let queue = DispatchQueue(label: CUSTOM_SERIAL_QUEUE_LABEL)
        asset.resourceLoader.setDelegate(self, queue: queue)
        
        // Create the player item and the player to play it back in.
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        
        // Create a new AVPlayerViewController and pass it a reference to the player.
        let controller = AVPlayerViewController()
        controller.player = player
        
        // Modally present the player and call the player's play() method when complete.
        present(controller, animated: true) {
            player.play()
        }
    }
    
    //Please note if your delegate method is not being called then you need to run on a REAL DEVICE
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        
        // Getting data for KSM server. Get the URL from tha manifest, we wil need it later as it
        // contains the assetId required for the license request.
        guard let url = loadingRequest.request.url else {
            print(#function, "Unable to read URL from loadingRequest")
            loadingRequest.finishLoading(with: NSError(domain: "", code: -1, userInfo: nil))
            return false
        }
        
        // Link to your certificate on BuyDRM's side.
        // Use the commented section if you want to refer the certificate from your bundle i.e. Store Locally
        
        /*
         guard let certificateURL = Bundle.main.url(forResource: "certificate", withExtension: "der"), let certificateData = try? Data(contentsOf: certificateURL) else {
         print("failed...", #function, "Unable to read the certificate data.")
         loadingRequest.finishLoading(with: NSError(domain: "com.domain.error", code: -2, userInfo: nil))
         return false
         }
         */
        
        guard let certificateData = try? Data(contentsOf: URL(string: CERTIFICATE_URL)!) else {
            print(#function, "Unable to read the certificate data.")
            loadingRequest.finishLoading(with: NSError(domain: "", code: -2, userInfo: nil))
            return false
        }
        
        // The assetId from the main/variant manifest - skd://xxx, the xxx part. Get the SPC based on the
        // already collected data i.e. certificate and the assetId
        guard let contentId = url.host, let contentIdData = contentId.data(using: String.Encoding.utf8) else {
            loadingRequest.finishLoading(with: NSError(domain: "", code: -3, userInfo: nil))
            print(#function, "Unable to read the SPC data.")
            return false
        }
        
        guard
            let spcData = try? loadingRequest.streamingContentKeyRequestData(forApp: certificateData, contentIdentifier: contentIdData, options: nil) else {
            loadingRequest.finishLoading(with: NSError(domain: "", code: -3, userInfo: nil))
            print(#function, "Unable to read the SPC data.")
            return false
        }
        
        // Prepare to get the license i.e. CKC.
        let requestUrl = CKC_URL
        let stringBody = "spc=\(spcData.base64EncodedString())&assetId=\(contentId)"
        let postData = NSData(data: stringBody.data(using: String.Encoding.utf8)!)
        
        // Make the POST request with customdata set to the authentication XML.
        var request = URLRequest(url: URL(string: requestUrl)!)
        request.httpMethod = "POST"
        request.httpBody = postData as Data
        request.allHTTPHeaderFields = ["customdata" : ACCESS_TOKEN]
        let configuration = URLSessionConfiguration.default
        let session = URLSession(configuration: configuration)
        let task = session.dataTask(with: request) { data, response, error in
            if let data = data {
                
                // The response from the KeyOS MultiKey License server may be an error inside JSON.
                do {
                    let parsedData = try JSONSerialization.jsonObject(with: data) as! [String:Any]
                    let errorId = parsedData["errorid"] as! String
                    let errorMsg = parsedData["errormsg"] as! String
                    print(#function, "License request failed with an error: \(errorMsg) [\(errorId)]")
                } catch let error as NSError {
                    print(#function, "The response may be a license. Moving on.", error)
                }
                
                // The response from the KeyOS MultiKey License server is Base64 encoded.
                let dataRequest = loadingRequest.dataRequest!
                
                // This command sends the CKC to the player.
                dataRequest.respond(with: Data(base64Encoded: data)!)
                loadingRequest.finishLoading()
            } else {
                print(#function, error?.localizedDescription ?? "Error during CKC request.")
            }
        }
        
        task.resume()
        
        // Tell the AVPlayer instance to wait. We are working on getting what it wants.
        return true
    }
}
