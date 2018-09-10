/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared
import SnapKit
import pop

class SyncDeviceTypeButton: UIControl {
    
    var imageView: UIImageView = UIImageView()
    var label: UILabel = UILabel()
    var pressed: Bool = false {
        didSet {
            if pressed {
                label.textColor = BraveUX.DefaultBlue
                if let anim = POPSpringAnimation(propertyNamed: kPOPLayerScaleXY) {
                    anim.toValue = NSValue(cgSize: CGSize(width: 0.9, height: 0.9))
                    layer.pop_add(anim, forKey: "size")
                }
            }
            else {
                label.textColor = UIColor.black
                if let anim = POPSpringAnimation(propertyNamed: kPOPLayerScaleXY) {
                    anim.toValue = NSValue(cgSize: CGSize(width: 1.0, height: 1.0))
                    layer.pop_add(anim, forKey: "size")
                }
            }
        }
    }
    
    convenience init(image: String, title: String) {
        self.init(frame: CGRect.zero)
        
        clipsToBounds = false
        backgroundColor = UIColor.white
        layer.cornerRadius = 12
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowRadius = 3
        layer.shadowOpacity = 0.1
        layer.shadowOffset = CGSize(width: 0, height: 1)
        
        imageView.image = UIImage(named: image)
        imageView.contentMode = .center
        imageView.tintColor = UIColor.black
        addSubview(imageView)
        
        label.text = title
        label.font = UIFont.systemFont(ofSize: 17.0, weight: UIFont.Weight.bold)
        label.textColor = UIColor.black
        label.textAlignment = .center
        addSubview(label)
        
        imageView.snp.makeConstraints { (make) in
            make.centerX.equalTo(self)
            make.centerY.equalTo(self).offset(-20)
        }
        
        label.snp.makeConstraints { (make) in
            make.top.equalTo(imageView.snp.bottom).offset(20)
            make.centerX.equalTo(self)
            make.width.equalTo(self)
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        pressed = true
        return true
    }
    
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        pressed = false
    }
    
    override func cancelTracking(with event: UIEvent?) {
        pressed = false
    }
}

class SyncAddDeviceTypeViewController: UIViewController {
    
    var scrollView: UIScrollView!
    var mobileButton: SyncDeviceTypeButton = SyncDeviceTypeButton(image: "sync-mobile", title: "Add a Mobile Device")
    var computerButton: SyncDeviceTypeButton = SyncDeviceTypeButton(image: "sync-computer", title: "Add a Computer")
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = Strings.Sync
        view.backgroundColor = SyncBackgroundColor
        
        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        
        edgesForExtendedLayout = UIRectEdge()
        
        scrollView.snp.makeConstraints { (make) in
            make.edges.equalTo(self.view)
        }
        
        scrollView.addSubview(mobileButton)
        scrollView.addSubview(computerButton)
        
        mobileButton.snp.makeConstraints { (make) in
            make.top.equalTo(20)
            make.left.right.equalTo(self.view).inset(15)
            make.height.equalTo(264)
        }
        
        computerButton.snp.makeConstraints { (make) in
            make.top.equalTo(mobileButton.snp.bottom).offset(20)
            make.left.right.equalTo(self.view).inset(15)
            make.height.equalTo(264)
        }
        
        mobileButton.addTarget(self, action: #selector(SEL_addMobile), for: .touchUpInside)
        computerButton.addTarget(self, action: #selector(SEL_addComputer), for: .touchUpInside)
    }
    
    @objc func SEL_addMobile() {
        let view = SyncAddDeviceViewController(title: "Add a Mobile Device", type: .mobile)
        navigationController?.pushViewController(view, animated: true)
    }
    
    @objc func SEL_addComputer() {
        let view = SyncAddDeviceViewController(title: "Add a Computer", type: .computer)
        navigationController?.pushViewController(view, animated: true)
    }
}

