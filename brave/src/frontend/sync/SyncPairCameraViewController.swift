/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared

class SyncPairCameraViewController: SyncViewController {

    var cameraView: SyncCameraView!
    var titleLabel: UILabel!
    var descriptionLabel: UILabel!
    var enterWordsButton: RoundInterfaceButton!
    
    fileprivate let prefs: Prefs = getApp().profile!.prefs
    var loadingView: UIView!
    let loadingSpinner = UIActivityIndicatorView(activityIndicatorStyle: .whiteLarge)
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = Strings.Pair
        
        // Start observing, this will handle child vc popping too for successful sync (e.g. pair words)
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: NotificationSyncReady), object: nil, queue: OperationQueue.main, using: {
            notification in
            self.navigationController?.popToRootViewController(animated: true)
        })

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.distribution = .equalSpacing
        stackView.alignment = .center
        stackView.spacing = 4
        view.addSubview(stackView)

        stackView.snp.makeConstraints { make in
            make.top.equalTo(self.topLayoutGuide.snp.bottom).offset(16)
            make.left.right.equalTo(self.view).inset(16)
            make.bottom.equalTo(self.view.safeArea.bottom).inset(16)
        }
        
        cameraView = SyncCameraView()
        cameraView.translatesAutoresizingMaskIntoConstraints = false
        cameraView.backgroundColor = UIColor.black
        cameraView.layer.cornerRadius = 4
        cameraView.layer.masksToBounds = true
        cameraView.scanCallback = { data in
            
            
            // TODO: Check data against sync api

            // TODO: Functional, but needs some cleanup
            struct Scanner { static var Lock = false }
            if let bytes = Niceware.shared.splitBytes(fromJoinedBytes: data) {
                if (Scanner.Lock) {
                    // Have internal, so camera error does not show
                    return
                }
                
                Scanner.Lock = true
                self.cameraView.cameraOverlaySucess()
                
                // Will be removed on pop
                self.loadingView.isHidden = false
                
                // Forced timeout
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(Int64(25.0) * Int64(NSEC_PER_SEC)) / Double(NSEC_PER_SEC), execute: {
                    Scanner.Lock = false
                    self.loadingView.isHidden = true
                    self.cameraView.cameraOverlayError()
                })
                
                // If multiple calls get in here due to race conditions it isn't a big deal
                
                Sync.shared.initializeSync(seed: bytes, deviceName: UIDevice.current.name)

            } else {
                self.cameraView.cameraOverlayError()
            }
        }

        stackView.addArrangedSubview(cameraView)

        let titleDescriptionStackView = UIStackView()
        titleDescriptionStackView.axis = .vertical
        titleDescriptionStackView.spacing = 4
        titleDescriptionStackView.alignment = .center
        titleDescriptionStackView.setContentCompressionResistancePriority(250, for: .vertical)
        
        titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 20, weight: UIFontWeightSemibold)
        titleLabel.textColor = BraveUX.GreyJ
        titleLabel.text = Strings.SyncToDevice
        titleDescriptionStackView.addArrangedSubview(titleLabel)

        descriptionLabel = UILabel()
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.font = UIFont.systemFont(ofSize: 15, weight: UIFontWeightRegular)
        descriptionLabel.textColor = BraveUX.GreyH
        descriptionLabel.numberOfLines = 0
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.textAlignment = .center
        descriptionLabel.text = Strings.SyncToDeviceDescription
        titleDescriptionStackView.addArrangedSubview(descriptionLabel)

        let textStackView = UIStackView(arrangedSubviews: [UIView.spacer(.horizontal, amount: 16),
                                                           titleDescriptionStackView,
                                                           UIView.spacer(.horizontal, amount: 16)])

        stackView.addArrangedSubview(textStackView)

        enterWordsButton = RoundInterfaceButton(type: .roundedRect)
        enterWordsButton.translatesAutoresizingMaskIntoConstraints = false
        enterWordsButton.setTitle(Strings.EnterCodeWords, for: .normal)
        enterWordsButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: UIFontWeightSemibold)
        enterWordsButton.setTitleColor(BraveUX.GreyH, for: .normal)
        enterWordsButton.addTarget(self, action: #selector(SEL_enterWords), for: .touchUpInside)
        stackView.addArrangedSubview(enterWordsButton)
        
        loadingSpinner.startAnimating()
        
        loadingView = UIView()
        loadingView.translatesAutoresizingMaskIntoConstraints = false
        loadingView.backgroundColor = UIColor(white: 0.5, alpha: 0.5)
        loadingView.isHidden = true
        loadingView.addSubview(loadingSpinner)
        stackView.addArrangedSubview(loadingView)
        
        edgesForExtendedLayout = UIRectEdge()

        cameraView.snp.makeConstraints { (make) in
            if DeviceDetector.isIpad {
                make.size.equalTo(400)
            } else {
                make.size.equalTo(self.view.snp.width).multipliedBy(0.9)
            }
        }

        loadingView.snp.makeConstraints { make in
            make.margins.equalTo(cameraView.snp.margins)
        }
        
        loadingSpinner.snp.makeConstraints { make in
            make.center.equalTo(loadingSpinner.superview!)
        }
    }
    
    func SEL_enterWords() {
        navigationController?.pushViewController(SyncPairWordsViewController(), animated: true)
    }
}

