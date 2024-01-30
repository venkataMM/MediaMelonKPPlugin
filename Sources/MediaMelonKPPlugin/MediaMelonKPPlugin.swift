//
//  MediaMelonKPPlugin.swift
//  BasicSample
//
//  Created by Media Melon on 25/01/24.
//  Copyright © 2024 Kaltura Inc. All rights reserved.
//

import Foundation
import AVFoundation
import os
#if os(iOS)
  import CoreTelephony
#endif
import PlayKit
import MMGenericFramework

public class MediaMelonKPPlugin: BasePlugin, MMSmartStreamingObserver {
    public func sessionInitializationCompleted(with status: MMSmartStreamingInitializationStatus, andDescription description: String!, forCmdWithId cmdId: Int, nowtilusPermission enableNowtilus: Bool) {}
    
    private enum CurrentPlayerState {
        case IDLE,
        PLAYING,
        PAUSED,
        STOPPED,
        ERROR
    }
        
    private enum BufferingState {
        case BUFFER_START,
        BUFFER_COMPLETE,
        NONE
    }
    
    private var  config: MediaMelonKPPluginConfig
    private var sdkVersion: String = "IOS" + MMSmartStreaming.getVersion() + "_KALTURA_v1.0.0"
    private var presentationInfoSet = false
    private var contentURL: String?
    private var currentState = CurrentPlayerState.IDLE
    private var currentAudioTrack = ""
    private var currentTextTrack = ""
    private var prevBufferState = BufferingState.NONE
    private var isAdPlaying = false
    
    lazy var mmSmartStreaming:MMSmartStreaming = MMSmartStreaming.getInstance() as! MMSmartStreaming
    private static var appNotificationObsRegistered = false
    private var presentationDuration = 0

    public override class var pluginName: String {
        return "MediaMelonKPPlugin"
    }
    
    @objc public func getVersion() -> String {
        return self.sdkVersion
    }
    
    public required init(player: Player, pluginConfig: Any?, messageBus: MessageBus) throws {
        guard let config = pluginConfig as? MediaMelonKPPluginConfig else {
            PKLog.error("missing plugin config or wrong plugin class type")
            throw PKPluginError.missingPluginConfig(pluginName: MediaMelonKPPlugin.pluginName)
        }
        self.config = config
        try super.init(player: player, pluginConfig: config, messageBus: messageBus)
                
        var component = "IOSSDK"
        #if os(tvOS)
            component = "tvOSSDK"
        #endif
        
        self.registerMMSmartStreaming(playerName: self.config.getPlayerName(), custID: self.config.getCustomerId(), component: component, subscriberID: self.config.getSubscriberId(), domainName: self.config.getDomainName(), subscriberType: self.config.getSubscriberType(), subscriberTag: self.config.getSubscriberTag(), hashSubscriberID: self.config.getHashSubscriberId())
        self.reportPlayerInfo(brand: self.config.getPlayerBrand(), model: self.config.getPlayerModel(), version: self.config.getPlayerName())
        
        MMSmartStreaming.disableManifestsFetch(self.config.getDisableManifestFetch())
        self.mmSmartStreaming.reportSDKVersion(self.sdkVersion)
        
        if #available(iOS 11.2, tvOS 11.2, *) {
            let availableModes = AVPlayer.availableHDRModes
            var deviceCapabilities = ""
            
            if availableModes.contains(.hlg) {
                deviceCapabilities += "HLG,";
            }

            if availableModes.contains(.hdr10) {
                deviceCapabilities += "HDR10,";
            }

            if availableModes.contains(.dolbyVision) {
                deviceCapabilities += "DolbyVision,";
            }
            
            if(deviceCapabilities.count > 0)
            {
                deviceCapabilities.removeLast();
            }
                        
            self.mmSmartStreaming.reportDeviceCapabilities(deviceCapabilities)
        }
        
        
        if (self.config.getVideoQuality() != "")
        {
            self.mmSmartStreaming.reportVideoQuality(self.config.getVideoQuality());
        }
        
        if (self.config.getDeviceId() != "")
        {
            self.mmSmartStreaming.reportDeviceID(self.config.getDeviceId());
        }
        
        if (self.config.getDeviceMarketingName() != "")
        {
            self.mmSmartStreaming.reportDeviceMarketingName(self.config.getDeviceMarketingName());
        }
        
        if (self.config.getAppName() != "" && self.config.getAppVersion() != "")
        {
            self.mmSmartStreaming.reportAppData(self.config.getAppName(), andVersion: self.config.getAppVersion());
        }
        
        self.registerEvents()
    }
    
    private func registerMMSmartStreaming(playerName: String, custID: String, component: String,  subscriberID: String?, domainName: String?, subscriberType: String?, subscriberTag: String?, hashSubscriberID: Bool) {
        MMSmartStreaming.registerForPlayer(withName: playerName, forCustID: custID, component: component, subsID: subscriberID, domainName: domainName, andSubscriberType: subscriberType, withTag:subscriberTag, hashSubID: hashSubscriberID);
        
        var operatorName = ""
        var osName = ""
        var osVersion = UIDevice.current.systemVersion
        let brand = "Apple"
        let model = UIDevice.current.model
        let screenWidth = Int(UIScreen.main.bounds.width)
        let screenHeight = Int(UIScreen.main.bounds.height)
        
        #if os(iOS)
            let phoneInfo = CTTelephonyNetworkInfo()
            if #available(iOS 12.0, *) {
                if let carrier = phoneInfo.serviceSubscriberCellularProviders, let dict = carrier.first, let opName = dict.value.carrierName {
                    operatorName = opName
                }
            }
            else {
                if let carrierName = phoneInfo.subscriberCellularProvider?.carrierName{
                    operatorName = carrierName
                }
            }
            osName = "iOS"
            MMSmartStreaming.reportDeviceInfo(withBrandName: brand, deviceModel: model, osName: osName, osVersion: osVersion, telOperator: operatorName, screenWidth: screenWidth, screenHeight: screenHeight, andType: model)
        #elseif os(tvOS)
            osName = "tvOS"
            MMSmartStreaming.reportDeviceInfo(withBrandName: brand, deviceModel: model, osName: osName, osVersion: osVersion, telOperator: operatorName, screenWidth: screenWidth, screenHeight: screenHeight, andType:"AppleTV")
        #endif
    }
    
    private func reportPlayerInfo(brand: String?, model: String?, version: String?) {
        MMSmartStreaming.reportPlayerInfo(withBrandName: brand, model: model, andVersion: version)
    }
    
    private func initializeSession() {
        let modeToRequest = MMQBRMode.QBRModeDisabled
        var connectionInfo: MMConnectionInfo!
        let reachability = ReachabilityMM()
        
        #if os(iOS)
        func getDetailedMobileNetworkType() {
            let phoneInfo = CTTelephonyNetworkInfo()
            if #available(iOS 12.0, *) {
                if let arrayNetworks = phoneInfo.serviceCurrentRadioAccessTechnology {
                    var networkString = ""
                    for value in arrayNetworks.values {
                        networkString = value
                    }
                    if networkString == CTRadioAccessTechnologyLTE{
                        connectionInfo = .cellular_4G
                    }else if networkString == CTRadioAccessTechnologyWCDMA{
                        connectionInfo = .cellular_3G
                    }else if networkString == CTRadioAccessTechnologyEdge{
                        connectionInfo = .cellular_2G
                    }
                }
            } else {
                let networkString = phoneInfo.currentRadioAccessTechnology
                if networkString == CTRadioAccessTechnologyLTE{
                    connectionInfo = .cellular_4G
                }else if networkString == CTRadioAccessTechnologyWCDMA{
                    connectionInfo = .cellular_3G
                }else if networkString == CTRadioAccessTechnologyEdge{
                    connectionInfo = .cellular_2G
                }
            }
        }
        #endif
        
        if let reachability = reachability{
            do{
                try reachability.startNotifier()
                let status = reachability.currentReachabilityStatus
                
                if(status == .notReachable){
                    connectionInfo = .notReachable
                }
                else if (status == .reachableViaWiFi){
                    connectionInfo = .wifi
                }
                else if (status == .reachableViaWWAN){
                    connectionInfo = .cellular
                    #if os(iOS)
                        getDetailedMobileNetworkType()
                    #endif
                }
            }
            catch{
                
            }
        }
        if (connectionInfo != nil) {
            self.mmSmartStreaming.reportNetworkType(connectionInfo)
        }
        let contentMetadata = MMContentMetadata()
        contentMetadata.assetId = self.config.getAssetId()
        contentMetadata.assetName = self.config.getAssetName()
        contentMetadata.videoId = self.config.getVideoId()
        contentMetadata.contentType = self.config.getContentType()
        contentMetadata.genre = self.config.getGenre()
        contentMetadata.season = self.config.getGenre()
        contentMetadata.drmProtection = self.config.getDrmProtection()
        contentMetadata.seriesTitle = self.config.getSeriesTitle()
        contentMetadata.episodeNumber = self.config.getEpisodeNumber()
        
        for (key, value) in self.config.getCustomTags() {
            self.mmSmartStreaming.reportCustomMetadata(withKey: key, andValue: value)
        }
        
        mmSmartStreaming.initializeSession(with: modeToRequest, registrationUri: "https://register.mediamelon.com/mm-apis/register/", forManifest: self.contentURL, metaURL: "", contentMetadata: contentMetadata, for: self)
    }
    
    private func reportUserInitiatedPlayback() {
        self.mmSmartStreaming.reportUserInitiatedPlayback()
    }
        
    public func reportError(error: String, playbackPosMilliSec: Int) {
        self.mmSmartStreaming.reportError(error, atPosition: playbackPosMilliSec)
    }
    
    @objc func reportMediaSelectionChange()
    {
        var isVDSActive = false
        var isSubtitleActive = false
        
        if currentAudioTrack.lowercased().contains("commentary") {
            isVDSActive = true
        }
        
        if(currentTextTrack != "Off" && currentTextTrack != "" && currentTextTrack != " ")
        {
            isSubtitleActive = true
        }
   
        mmSmartStreaming.reportMediaTrackInfo( isSubtitleActive , subtitleTrack: currentTextTrack, audioTrack: currentAudioTrack, isVDSActive:  isVDSActive)
    }
    
    private func setPresentationInformation(presentationInfo: MMPresentationInfo!) {
        self.mmSmartStreaming.setPresentationInformation(presentationInfo)
    }
    
    private func reportBufferingStarted() {
        self.mmSmartStreaming.reportBufferingStarted()
    }
    
    private func reportBufferingCompleted() {
        self.mmSmartStreaming.reportBufferingCompleted()
    }
    
    @objc private func timeoutOccurred() {
        self.mmSmartStreaming.reportPlaybackPosition(getPlaybackPosition())
    }
    
    private func getPlaybackPosition() -> Int {
        guard let player = self.player else{
            return 0
        }
        
        let time = player.currentTime
        return Int(time*1000);
    }
    
    private func reportPlayerSeekCompleted(seekEndPos: Int) {
        self.mmSmartStreaming.reportPlayerSeekCompleted(seekEndPos)
    }
    
    private func processDuration() {
        guard self.player != nil else {
            return;
        }
        
        self.presentationDuration = Int((self.player?.duration ?? 0) * 1000)
        self.setPresentationInformationForContent()
    }
    
    private func setPresentationInformationForContent() {
        let contentDuration = presentationDuration

        if !self.presentationInfoSet {
            let presentationInfo = MMPresentationInfo()
            let hasValidDuration = (contentDuration > 0)
            if(hasValidDuration){
                presentationInfo.duration = Int(contentDuration)
            } else {
                presentationInfo.duration = Int(-1)
            }
            presentationInfo.isLive = (self.player?.isLive() ?? false)
            self.mmSmartStreaming.setPresentationInformation(presentationInfo)
            self.presentationInfoSet = true
        }
    }
    
    private func replaySession(){
        guard self.player != nil else{
            return
        }
        
        self.initializeSession()
        self.reportUserInitiatedPlayback();
        self.setPresentationInformationForContent()
    }
    
    private func reportStoppedState() {
        if(self.currentState != .IDLE && self.currentState != .STOPPED) {
            if let player = self.player {
                let time = player.currentTime;
                self.mmSmartStreaming.reportPlaybackPosition(Int(time*1000))
            }
            self.mmSmartStreaming.report(.STOPPED)
            self.currentState = .STOPPED
        }
    }


    /************************************************************/
    // MARK: - player Events Register
    /************************************************************/

    public var playerEventsToRegister: [PlayerEvent.Type] {
        return [
            PlayerEvent.stateChanged,
            PlayerEvent.loadedMetadata,
            PlayerEvent.play,
            PlayerEvent.pause,
            PlayerEvent.playing,
            PlayerEvent.playbackRate,
            PlayerEvent.seeking,
            PlayerEvent.seeked,
            PlayerEvent.durationChanged,
            PlayerEvent.sourceSelected,
            PlayerEvent.stopped,
            PlayerEvent.ended,
            PlayerEvent.replay,
            PlayerEvent.tracksAvailable,
            PlayerEvent.textTrackChanged,
            PlayerEvent.audioTrackChanged,
            PlayerEvent.videoTrackChanged,
            PlayerEvent.error,
            PlayerEvent.playheadUpdate
        ]
    }
    
    public var adEventsToRegister: [AdEvent.Type] {
        return [
            AdEvent.adsRequested,
            AdEvent.adLoaded,
            AdEvent.adStarted,
            AdEvent.adFirstQuartile,
            AdEvent.adMidpoint,
            AdEvent.adThirdQuartile,
            AdEvent.adPaused,
            AdEvent.adResumed,
            AdEvent.adComplete,
            AdEvent.adSkipped,
            AdEvent.allAdsCompleted,
            AdEvent.adClicked,
            AdEvent.adDidRequestContentPause,
            AdEvent.adDidRequestContentResume,
            AdEvent.requestTimedOut,
            AdEvent.error,
            AdEvent.adDidProgressToTime
        ]
    }
    
    public func registerEvents() {
        self.messageBus?.addObserver(self, events: playerEventsToRegister, block: { [weak self] event in
            guard let self = self else { return }
            
            switch event {
                case is PlayerEvent.LoadedMetadata:
                    self.mmSmartStreaming.reportManifestLoaded()
                case is PlayerEvent.Ended:
                    self.reportStoppedState()
                case is PlayerEvent.Play:
                    self.mmSmartStreaming.report(MMPlayerState.PLAYING)
                    self.currentState = CurrentPlayerState.PLAYING
                case is PlayerEvent.Playing:
                    self.mmSmartStreaming.report(MMPlayerState.PLAYING)
                    self.currentState = CurrentPlayerState.PLAYING
                case is PlayerEvent.Error:
                    let errorMessage = "(" + String(event.error?.code ?? 0) + ") " + (event.error?.localizedDescription ?? "")
                    self.reportError(error: errorMessage, playbackPosMilliSec: self.getPlaybackPosition())
                case is PlayerEvent.Pause:
                    self.mmSmartStreaming.report(MMPlayerState.PAUSED)
                    self.currentState = CurrentPlayerState.PAUSED
                case is PlayerEvent.Seeking:
                    self.mmSmartStreaming.reportPlayerSeekStarted()
                case is PlayerEvent.Seeked:
                    self.mmSmartStreaming.reportPlayerSeekCompleted(self.getPlaybackPosition())
                case is PlayerEvent.DurationChanged:
                    self.processDuration()
                case is PlayerEvent.PlaybackInfo: break
                case is PlayerEvent.TracksAvailable:
                    event.tracks?.audioTracks?.forEach{ audioTrack in
                        if(audioTrack.id == self.player?.currentAudioTrack) {
                            self.currentAudioTrack = audioTrack.title
                        }
                    }
                    event.tracks?.textTracks?.forEach{ textTrack in
                        if(textTrack.id == self.player?.currentTextTrack) {
                            self.currentTextTrack = textTrack.title
                        }
                    }
                    self.reportMediaSelectionChange()
                case is PlayerEvent.Replay:
                    self.replaySession()
                case is PlayerEvent.PlayheadUpdate:
                    self.timeoutOccurred()
                case is PlayerEvent.VideoTrackChanged: break
                case is PlayerEvent.AudioTrackChanged:
                    if (event.selectedTrack?.title != nil)
                    {
                        self.currentAudioTrack = event.selectedTrack?.title ?? ""
                        self.reportMediaSelectionChange()
                    }
                case is PlayerEvent.TextTrackChanged:
                    if (event.selectedTrack?.title != nil)
                    {
                        self.currentTextTrack = event.selectedTrack?.title ?? ""
                        self.reportMediaSelectionChange()
                    }
                case is PlayerEvent.StateChanged:
                    switch event.newState {
                    case .buffering:
                        if(self.prevBufferState != BufferingState.BUFFER_START)
                        {
                            self.reportBufferingStarted()
                            self.prevBufferState = BufferingState.BUFFER_START
                        }
                    case .ready:
                        if(self.prevBufferState == BufferingState.BUFFER_START)
                        {
                            self.reportBufferingCompleted()
                            self.prevBufferState = BufferingState.BUFFER_COMPLETE
                        }
                    default:
                        break
                    }
                default:
                    break
            }
        })
        
        self.messageBus?.addObserver(self, events: adEventsToRegister, block: { [weak self] event in
            guard let self = self else { return }
            
            switch event {
                case is AdEvent.AdsRequested:
                    self.mmSmartStreaming.report(.AD_REQUEST)
                case is AdEvent.AdLoaded:
                    let adInfo = MMAdInfo()
                    adInfo.adClient = event.adInfo?.advertiserName
                    adInfo.adId = event.adInfo?.adId
                    adInfo.adTitle = event.adInfo?.title
                    adInfo.adCreativeId = event.adInfo?.creativeId
                    adInfo.adDuration = Int((event.adInfo?.duration ?? 0) * 1000)
                    adInfo.adCreativeType = event.adInfo?.contentType
                    adInfo.adResolution = "\(event.adInfo?.width ?? 0)x\(event.adInfo?.height ?? 0)"
                    adInfo.adServer = event.adInfo?.adSystem
                    adInfo.adUrl = event.adTagUrl
                    adInfo.adBitrate = event.adInfo?.mediaBitrate ?? 0
                    switch event.adInfo?.positionType {
                        case .preRoll:
                            adInfo.adPosition = "pre"
                        case .midRoll:
                            adInfo.adPosition = "mid"
                        case .postRoll:
                            adInfo.adPosition = "post"
                        default:
                            break
                    }
                    adInfo.adPodIndex = event.adInfo?.podIndex ?? -1
                    adInfo.adPodLendth = event.adInfo?.totalAds ?? -1
                    adInfo.adPositionInPod = event.adInfo?.adIndexInPod ?? -1
                    adInfo.isBumper = event.adInfo?.isBumper ?? false
                    self.mmSmartStreaming.report(adInfo)
                    self.mmSmartStreaming.report(.AD_IMPRESSION)
                case is AdEvent.AdStarted:
                    self.isAdPlaying = true
                    self.mmSmartStreaming.report(.AD_STARTED)
                case is AdEvent.AdFirstQuartile:
                    self.mmSmartStreaming.report(.AD_FIRST_QUARTILE)
                case is AdEvent.AdMidpoint:
                    self.mmSmartStreaming.report(.AD_MIDPOINT)
                case is AdEvent.AdThirdQuartile:
                    self.mmSmartStreaming.report(.AD_THIRD_QUARTILE)
                case is AdEvent.AdPaused:
                    self.mmSmartStreaming.report(.AD_PAUSED)
                case is AdEvent.AdResumed:
                    self.mmSmartStreaming.report(.AD_RESUMED)
                case is AdEvent.AdComplete:
                    self.isAdPlaying = false
                    self.mmSmartStreaming.report(.AD_COMPLETED)
                case is AdEvent.AdSkipped:
                    self.isAdPlaying = false
                    self.mmSmartStreaming.report(.AD_SKIPPED)
                case is AdEvent.AllAdsCompleted:
                    self.isAdPlaying = false
                case is AdEvent.AdClicked:
                    self.mmSmartStreaming.report(.AD_CLICKED)
                case is AdEvent.AdDidRequestContentPause:
                    self.mmSmartStreaming.report(MMPlayerState.PAUSED)
                case is AdEvent.AdDidRequestContentResume:
                    self.mmSmartStreaming.report(MMPlayerState.PLAYING)
                case is AdEvent.RequestTimedOut:
                    self.isAdPlaying = false
                    self.mmSmartStreaming.report(.AD_ERROR)
                    let pos = Int(Double(truncating: event.adMediaTime ?? 0.0) * 1000)
                    self.mmSmartStreaming.reportAdError("Ad Request Timed out", atPlaybackPos: pos)
                case is AdEvent.Error:
                    self.isAdPlaying = false
                    self.mmSmartStreaming.report(.AD_ERROR)
                    let pos = Int(Double(truncating: event.adMediaTime ?? 0.0) * 1000)
                    self.mmSmartStreaming.reportAdError(event.adError?.localizedDescription, atPlaybackPos: pos)
                case is AdEvent.AdDidProgressToTime:
                    let pos = Int(Double(truncating: event.adMediaTime ?? 0.0) * 1000)
                    self.mmSmartStreaming.reportAdPlaybackTime(pos)
                default:
                    break
                }
        })
    }
    
    public func unregisterEvents() {
        self.messageBus?.removeObserver(self, events: playerEventsToRegister)
        self.messageBus?.removeObserver(self, events: adEventsToRegister)
    }
    
    private func reset() {
        self.presentationInfoSet = false
        self.contentURL = nil
        self.currentState = CurrentPlayerState.IDLE
        self.currentAudioTrack = ""
        self.currentTextTrack = ""
        self.prevBufferState = BufferingState.NONE
        self.isAdPlaying = false
    }
    
    public override func onUpdateMedia(mediaConfig: MediaConfig) {
        PKLog.debug("onUpdateMedia: \(String(describing: mediaConfig))")
        super.onUpdateMedia(mediaConfig: mediaConfig)
        
        self.reset()
        self.contentURL = mediaConfig.mediaEntry.sources?[0].contentUrl?.absoluteString
        self.initializeSession()
        self.reportUserInitiatedPlayback();
    }
    
    public override func onUpdateConfig(pluginConfig: Any) {
        super.onUpdateConfig(pluginConfig: pluginConfig)
    }
    
    public override func destroy() {
        self.unregisterEvents()
        super.destroy()
    }
}
