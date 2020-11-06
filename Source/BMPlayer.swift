//
//  BMPlayer.swift
//  Pods
//
//  Created by BrikerMan on 16/4/28.
//
//

import UIKit
import SnapKit
import MediaPlayer

/// BMPlayerDelegate to obserbe player state
public protocol BMPlayerDelegate : class {
    func bmPlayer(player: BMPlayer, playerStateDidChange state: BMPlayerState)
    func bmPlayer(player: BMPlayer, loadedTimeDidChange loadedDuration: TimeInterval, totalDuration: TimeInterval)
    func bmPlayer(player: BMPlayer, playTimeDidChange currentTime : TimeInterval, totalTime: TimeInterval)
    func bmPlayer(player: BMPlayer, playerIsPlaying playing: Bool)
    func bmPlayer(player: BMPlayer, playerOrientChanged isFullscreen: Bool)
}

/**
 internal enum to check the pan direction
 
 - horizontal: horizontal
 - vertical:   vertical
 */
enum BMPanDirection: Int {
    case horizontal = 0
    case vertical   = 1
}

open class BMPlayer: UIView {
    
    open weak var delegate: BMPlayerDelegate?
    
    open var backBlock:((Bool) -> Void)?
    
    /// Gesture to change volume / brightness
    open var panGesture: UIPanGestureRecognizer!
    
    /// AVLayerVideoGravityType
    open var videoGravity = AVLayerVideoGravity.resizeAspect {
        didSet {
            playerLayer?.videoGravity = videoGravity
        }
    }
    
    open var isPlaying: Bool {
        get {
            return playerLayer?.isPlaying ?? false
        }
    }
    
    //Closure fired when play time changed
    open var playTimeDidChange:((TimeInterval, TimeInterval) -> Void)?

    //Closure fired when play state chaged

    open var playOrientChanged:((Bool) -> Void)?

    open var isPlayingStateChanged:((Bool) -> Void)?

    open var playStateChanged:((BMPlayerState) -> Void)?
    
    open var avPlayer: AVPlayer? {
        return playerLayer?.player
    }
    
    open var playerLayer: BMPlayerLayerView?
    
    fileprivate var resource: BMPlayerResource!
    
    fileprivate var currentDefinition = 0
    
    fileprivate var controlView: BMPlayerControlView!
    
    fileprivate var customControlView: BMPlayerControlView?
    
    fileprivate var isFullScreen:Bool {
        get {
            return UIApplication.shared.statusBarOrientation.isLandscape
        }
    }
    
    /// 滑动方向
    fileprivate var panDirection = BMPanDirection.horizontal
    
    /// 音量滑竿
    fileprivate var volumeViewSlider: UISlider!
    
    fileprivate let BMPlayerAnimationTimeInterval: Double             = 4.0
    fileprivate let BMPlayerControlBarAutoFadeOutTimeInterval: Double = 0.5
    
    /// 用来保存时间状态
    fileprivate var sumTime         : TimeInterval = 0
    fileprivate var totalDuration   : TimeInterval = 0
    fileprivate var currentPosition : TimeInterval = 0
    fileprivate var shouldSeekTo    : TimeInterval = 0
    
    fileprivate var isURLSet        = false
    fileprivate var isSliderSliding = false
    fileprivate var isPauseByUser   = false
    fileprivate var isVolume        = false
    fileprivate var isMaskShowing   = false
    fileprivate var isSlowed        = false
    fileprivate var isMirrored      = false
    fileprivate var isPlayToTheEnd  = false
    //视频画面比例
    fileprivate var aspectRatio: BMPlayerAspectRatio = .default
    
    //Cache is playing result to improve callback performance
    fileprivate var isPlayingCache: Bool? = nil
    
    // MARK: - Public functions
    
    /**
     Play
     
     - parameter resource:        media resource
     - parameter definitionIndex: starting definition index, default start with the first definition
     */
    open func setVideo(resource: BMPlayerResource, definitionIndex: Int = 0) {
        isURLSet = false
        self.resource = resource
        
        currentDefinition = definitionIndex
        controlView.prepareUI(for: resource, selectedIndex: definitionIndex)
        
        if BMPlayerConf.shouldAutoPlay {
            isURLSet = true
            let asset = resource.definitions[definitionIndex]
            playerLayer?.playAsset(asset: asset.avURLAsset)
        } else {
            controlView.showCover(url: resource.cover)
            controlView.hideLoader()
        }
    }
    
    /**
     auto start playing, call at viewWillAppear, See more at pause
     */
    open func autoPlay() {
        if !isPauseByUser && isURLSet && !isPlayToTheEnd {
            play()
        }
    }
    
    /**
     Play
     */
    open func play() {
        guard resource != nil else { return }
        
        if !isURLSet {
            let asset = resource.definitions[currentDefinition]
            playerLayer?.playAsset(asset: asset.avURLAsset)
            controlView.hideCoverImageView()
            isURLSet = true
        }
        
        panGesture.isEnabled = true
        playerLayer?.play()
        isPauseByUser = false
    }
    
    /**
     Pause
     
     - parameter allow: should allow to response `autoPlay` function
     */
    open func pause(allowAutoPlay allow: Bool = false) {
        playerLayer?.pause()
        isPauseByUser = !allow
    }
    
    /**
     seek
     
     - parameter to: target time
     */
    open func seek(_ to:TimeInterval, completion: ((Bool)->Void)? = nil) {
        playerLayer?.seek(to: to, completion: completion)
    }
    
    /**
     update UI to fullScreen
     */
    open func updateUI(_ isFullScreen: Bool) {
        controlView.updateUI(isFullScreen)
    }
    
    /**
     increade volume with step, default step 0.1
     
     - parameter step: step
     */
    open func addVolume(step: Float = 0.1) {
        volumeViewSlider.value += step
    }
    
    /**
     decreace volume with step, default step 0.1
     
     - parameter step: step
     */
    open func reduceVolume(step: Float = 0.1) {
        volumeViewSlider.value -= step
    }
    
    /**
     prepare to dealloc player, call at View or Controllers deinit funciton.
     */
    open func prepareToDealloc() {
        playerLayer?.prepareToDeinit()
        controlView.prepareToDealloc()
    }
    
    /**
     If you want to create BMPlayer with custom control in storyboard.
     create a subclass and override this method.
     
     - return: costom control which you want to use
     */
    open func storyBoardCustomControl() -> BMPlayerControlView? {
        return nil
    }
    
    // MARK: - Action Response
    
    @objc fileprivate func panDirection(_ pan: UIPanGestureRecognizer) {
        // 根据在view上Pan的位置，确定是调音量还是亮度
        let locationPoint = pan.location(in: self)
        
        // 我们要响应水平移动和垂直移动
        // 根据上次和本次移动的位置，算出一个速率的point
        let velocityPoint = pan.velocity(in: self)
        
        // 判断是垂直移动还是水平移动
        switch pan.state {
        case .began:
            // 使用绝对值来判断移动的方向
            let x = abs(velocityPoint.x)
            let y = abs(velocityPoint.y)
            
            if x > y {
                if BMPlayerConf.enablePlaytimeGestures {
                    panDirection = BMPanDirection.horizontal
                    
                    // 给sumTime初值
                    if let player = playerLayer?.player {
                        let time = player.currentTime()
                        sumTime = TimeInterval(time.value) / TimeInterval(time.timescale)
                    }
                }
            } else {
                panDirection = BMPanDirection.vertical
                if locationPoint.x > bounds.size.width / 2 {
                    isVolume = true
                } else {
                    isVolume = false
                }
            }
            
        case .changed:
            switch panDirection {
            case BMPanDirection.horizontal:
                horizontalMoved(velocityPoint.x)
            case BMPanDirection.vertical:
                verticalMoved(velocityPoint.y)
            }
            
        case .ended, .cancelled:
            // 移动结束也需要判断垂直或者平移
            // 比如水平移动结束时，要快进到指定位置，如果这里没有判断，当我们调节音量完之后，会出现屏幕跳动的bug
            switch (panDirection) {
            case BMPanDirection.horizontal:
                controlView.hideSeekToView()
                if isPlayToTheEnd {
                    isPlayToTheEnd = false
                    seek(sumTime, completion: {[weak self] in
                        if $0 { self?.play() }
                        self?.isSliderSliding = false
                    })
                } else {
                    seek(sumTime, completion: {[weak self] in
                        if $0 { self?.autoPlay() }
                        self?.isSliderSliding = false
                    })
                }
                // 把sumTime滞空，不然会越加越多
                sumTime = 0.0
                
            case BMPanDirection.vertical:
                isVolume = false
            }
        default:
            break
        }
    }
    
    fileprivate func verticalMoved(_ value: CGFloat) {
        if BMPlayerConf.enableVolumeGestures && isVolume{
            volumeViewSlider.value -= Float(value / 10000)
        }
        else if BMPlayerConf.enableBrightnessGestures && !isVolume{
            UIScreen.main.brightness -= value / 10000
        }
    }
    
    fileprivate func horizontalMoved(_ value: CGFloat) {
        guard BMPlayerConf.enablePlaytimeGestures else { return }
        
        isSliderSliding = true
        if let playerItem = playerLayer?.playerItem {
            // 每次滑动需要叠加时间，通过一定的比例，使滑动一直处于统一水平
            sumTime = sumTime + TimeInterval(value) / 100.0 * (TimeInterval(totalDuration)/400)
            
            let totalTime = playerItem.duration
            
            // 防止出现NAN
            if totalTime.timescale == 0 { return }
            
            let totalDuration = TimeInterval(totalTime.value) / TimeInterval(totalTime.timescale)
            if (sumTime >= totalDuration) { sumTime = totalDuration }
            if (sumTime <= 0) { sumTime = 0 }
            
            controlView.showSeekToView(to: sumTime, total: totalDuration, isAdd: value > 0)
        }
    }
    
    @objc open func onOrientationChanged() {
        updateUI(isFullScreen)
        delegate?.bmPlayer(player: self, playerOrientChanged: isFullScreen)
        playOrientChanged?(isFullScreen)
    }
    
    @objc fileprivate func fullScreenButtonPressed() {
        controlView.updateUI(!isFullScreen)
        if isFullScreen {
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
//            UIApplication.shared.setStatusBarHidden(false, with: .fade)
//            UIApplication.shared.statusBarOrientation = .portrait
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
//            UIApplication.shared.setStatusBarHidden(false, with: .fade)
//            UIApplication.shared.statusBarOrientation = .landscapeRight
        }
    }
    
    // MARK: - 生命周期
    deinit {
        playerLayer?.pause()
        playerLayer?.prepareToDeinit()
        NotificationCenter.default.removeObserver(self, name: UIApplication.didChangeStatusBarOrientationNotification, object: nil)
        NotificationCenter.default.removeObserver(activeObserver as Any)
    }
    
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        if let customControlView = storyBoardCustomControl() {
            self.customControlView = customControlView
        }
        initUI()
        initUIData()
        configureVolume()
        preparePlayer()
    }
        
    public init(customControlView: BMPlayerControlView?) {
        super.init(frame:CGRect.zero)
        self.customControlView = customControlView
        initUI()
        initUIData()
        configureVolume()
        preparePlayer()
    }
    
    public convenience init() {
        self.init(customControlView:nil)
    }
    
    // MARK: - 初始化
    fileprivate func initUI() {
        backgroundColor = UIColor.black
        
        if let customView = customControlView {
            controlView = customView
        } else {
            controlView = BMPlayerControlView()
        }
        
        addSubview(controlView)
        controlView.updateUI(isFullScreen)
        controlView.delegate = self
        controlView.player   = self
        controlView.snp.makeConstraints { (make) in
            make.edges.equalTo(self)
        }
        
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(panDirection(_:)))
        addGestureRecognizer(panGesture)
    }
    
    fileprivate func initUIData() {
        NotificationCenter.default.addObserver(self, selector: #selector(onOrientationChanged), name: UIApplication.didChangeStatusBarOrientationNotification, object: nil)
    }
    
    fileprivate func configureVolume() {
        let volumeView = MPVolumeView()
        for view in volumeView.subviews {
            if let slider = view as? UISlider {
                volumeViewSlider = slider
            }
        }
    }
    
    private var activeObserver: NSObjectProtocol?
    
    fileprivate func preparePlayer() {
        playerLayer = BMPlayerLayerView()
        playerLayer!.shouldLoopPlay = BMPlayerConf.shouldLoopPlay
        playerLayer!.videoGravity = videoGravity
        insertSubview(playerLayer!, at: 0)
        playerLayer!.snp.makeConstraints { [weak self](make) in
          guard let `self` = self else { return }
          make.edges.equalTo(self)
        }
        playerLayer!.delegate = self
        controlView.showLoader()
        layoutIfNeeded()
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self]_ in
            guard let self = self else { return }
            if self.isPlaying { self.play() }
        }
    }
}

extension BMPlayer: BMPlayerLayerViewDelegate {
    public func bmPlayer(player: BMPlayerLayerView, playerIsPlaying playing: Bool) {
        controlView.playStateDidChange(isPlaying: playing)
        delegate?.bmPlayer(player: self, playerIsPlaying: playing)
        isPlayingStateChanged?(player.isPlaying)
    }
    
    public func bmPlayer(player: BMPlayerLayerView, loadedTimeDidChange loadedDuration: TimeInterval, totalDuration: TimeInterval) {
        BMPlayerManager.shared.log("loadedTimeDidChange - \(loadedDuration) - \(totalDuration)")
        controlView.loadedTimeDidChange(loadedDuration: loadedDuration, totalDuration: totalDuration)
        delegate?.bmPlayer(player: self, loadedTimeDidChange: loadedDuration, totalDuration: totalDuration)
        controlView.totalDuration = totalDuration
        self.totalDuration = totalDuration
    }
    
    public func bmPlayer(player: BMPlayerLayerView, playerStateDidChange state: BMPlayerState) {
        BMPlayerManager.shared.log("playerStateDidChange - \(state)")
        
        controlView.playerStateDidChange(state: state)
        switch state {
        case .readyToPlay:
            if !isPauseByUser {
                play()
            }
            if shouldSeekTo != 0 {
                seek(shouldSeekTo, completion: {[weak self] in
                    guard $0, let `self` = self else { return }
                    if !self.isPauseByUser {
                        self.play()
                    } else {
                        self.pause()
                    }
                })
            }
            
        case .bufferFinished:
            autoPlay()
            
        case .playedToTheEnd:
            isPlayToTheEnd = true
            
        default:
            break
        }
        panGesture.isEnabled = state != .playedToTheEnd
        delegate?.bmPlayer(player: self, playerStateDidChange: state)
        playStateChanged?(state)
    }
    
    public func bmPlayer(player: BMPlayerLayerView, playTimeDidChange currentTime: TimeInterval, totalTime: TimeInterval) {
        BMPlayerManager.shared.log("playTimeDidChange - \(currentTime) - \(totalTime)")
        delegate?.bmPlayer(player: self, playTimeDidChange: currentTime, totalTime: totalTime)
        currentPosition = currentTime
        totalDuration = totalTime
        if isSliderSliding {
            return
        }
        controlView.playTimeDidChange(currentTime: currentTime, totalTime: totalTime)
        controlView.totalDuration = totalDuration
        playTimeDidChange?(currentTime, totalTime)
    }
}

extension BMPlayer: BMPlayerControlViewDelegate {
    open func controlView(controlView: BMPlayerControlView,
                          didChooseDefinition index: Int) {
        shouldSeekTo = currentPosition
        playerLayer?.resetPlayer()
        currentDefinition = index
        playerLayer?.playAsset(asset: resource.definitions[index].avURLAsset)
    }
    
    open func controlView(controlView: BMPlayerControlView,
                          didPressButton button: UIButton) {
        if let action = BMPlayerControlView.ButtonType(rawValue: button.tag) {
            switch action {
            case .back:
                backBlock?(isFullScreen)
                if isFullScreen {
                    fullScreenButtonPressed()
                } else {
                    playerLayer?.prepareToDeinit()
                }
                
            case .play:
                if button.isSelected {
                    pause()
                } else {
                    if isPlayToTheEnd {
                        seek(0, completion: {[weak self] in
                            if $0 { self?.play() }
                        })
                        controlView.hidePlayToTheEndView()
                        isPlayToTheEnd = false
                    }
                    play()
                }
                
            case .replay:
                isPlayToTheEnd = false
                seek(0)
                play()
                
            case .fullscreen:
                fullScreenButtonPressed()
                
            default:
                print("[Error] unhandled Action")
            }
        }
    }
    
    open func controlView(controlView: BMPlayerControlView,
                          slider: UISlider,
                          onSliderEvent event: UIControl.Event) {
        switch event {
        case .touchDown:
            playerLayer?.onTimeSliderBegan()
            isSliderSliding = true
            
        case .touchUpInside :
            let target = totalDuration * Double(slider.value)
            
            if isPlayToTheEnd {
                isPlayToTheEnd = false
                seek(target, completion: {[weak self] in
                    guard $0 else { return }
                    self?.play()
                    self?.isSliderSliding = false
                })
                controlView.hidePlayToTheEndView()
            } else {
                seek(target, completion: {[weak self] in
                    guard $0 else { return }
                    self?.autoPlay()
                    self?.isSliderSliding = false
                })
            }
        default:
            break
        }
    }
    
    open func controlView(controlView: BMPlayerControlView, didChangeVideoAspectRatio: BMPlayerAspectRatio) {
        playerLayer?.aspectRatio = aspectRatio
    }
    
    open func controlView(controlView: BMPlayerControlView, didChangeVideoPlaybackRate rate: Float) {
        playerLayer?.player?.rate = rate
    }
}
