//
//  MenuBarExtraAccess.swift
//  MenuBarExtraAccess • https://github.com/orchetect/MenuBarExtraAccess
//  © 2023 Steffan Andrews • Licensed under MIT License
//

#if os(macOS)

import SwiftUI
import Combine

@available(macOS 13.0, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension Scene {
    /// Adds a presentation state binding to `MenuBarExtra`.
    /// If more than one MenuBarExtra are used in the app, provide the sequential index number of the `MenuBarExtra`.
    public func menuBarExtraAccess(
        index: Int = 0,
        isPresented: Binding<Bool>,
        statusItem: ((_ statusItem: NSStatusItem) -> Void)? = nil
    ) -> some Scene {
        // FYI: SwiftUI will reinitialize the MenuBarExtra (and this view modifier)
        // if its title/label content changes, which means the stored ID will always be up-to-date
        
        MenuBarExtraAccess(
            index: index,
            statusItemIntrospection: statusItem,
            menuBarExtra: self,
            isMenuPresented: isPresented
        )
    }
}

@available(macOS 13.0, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
struct MenuBarExtraAccess<Content: Scene>: Scene {
    let index: Int
    let statusItemIntrospection: ((_ statusItem: NSStatusItem) -> Void)?
    let menuBarExtra: Content
    @Binding var isMenuPresented: Bool
    
    init(
        index: Int,
        statusItemIntrospection: ((_ statusItem: NSStatusItem) -> Void)?,
        menuBarExtra: Content,
        isMenuPresented: Binding<Bool>
    ) {
        self.index = index
        self.statusItemIntrospection = statusItemIntrospection
        self.menuBarExtra = menuBarExtra
        self._isMenuPresented = isMenuPresented
    }
    
    var body: some Scene {
        menuBarExtra
            .onChange(of: observerSetup()) { newValue in
                // do nothing here - the method runs setup when polled by SwiftUI
            }
            .onChange(of: isMenuPresented) { newValue in
                setPresented(newValue)
            }
    }
    
    private func togglePresented() {
        MenuBarExtraUtils.togglePresented(for: .index(index))
    }
    
    private func setPresented(_ state: Bool) {
        MenuBarExtraUtils.setPresented(for: .index(index), state: state)
    }
    
    // MARK: Observer
    
    /// A workaround since `onAppear {}` is not available in a SwiftUI Scene.
    /// We need to set up the observer, but it can't be set up in the scene init because it needs to
    /// update scene state from an escaping closure.
    /// This returns a bogus value, but because we call it in an `onChange {}` block, SwiftUI
    /// is forced to evaluate the method and run our code at the appropriate time.
    private func observerSetup() -> Int {
        observerContainer.setupStatusItemIntrospection {
            guard let statusItem = MenuBarExtraUtils.statusItem(for: .index(index)) else { return }
            statusItemIntrospection?(statusItem)
        }
        
        // note that we can't use the button state value itself since MenuBarExtra seems to treat it
        // as a toggle and not an absolute on/off value. Its polarity can invert itself when clicking
        // in an empty area of the menubar or a different app's status item in order to dismiss the window,
        // for example.
        observerContainer.setupStatusItemButtonStateObserver {
            MenuBarExtraUtils.newStatusItemButtonStateObserver(index: index) { change in
                #if DEBUG
                print("Status item button state observer: called with change: \(change.newValue?.description ?? "nil")")
                #endif
                
                // only continue if the MenuBarExtra is menu-based.
                // window-based MenuBarExtras are handled with app-bound window observers instead.
                guard MenuBarExtraUtils.statusItem(for: .index(index))?
                    .isMenuBarExtraMenuBased == true
                else { return }
                
                guard let newVal = change.newValue else { return }
                let newBool = newVal != .off
                if isMenuPresented != newBool {
                    #if DEBUG
                    print("Status item button state observer: Setting isMenuPresented to \(newBool)")
                    #endif
                    
                    isMenuPresented = newBool
                }
            }
        }
        
        // TODO: this mouse event observer is now redundant and can be deleted in the future
        
        // observerContainer.setupGlobalMouseDownMonitor {
        //     // note that this won't fire when mouse events within the app cause the window to dismiss
        //     MenuBarExtraUtils.newGlobalMouseDownEventsMonitor { event in
        //         #if DEBUG
        //         print("Global mouse-down events monitor: called with event: \(event.type)")
        //         #endif
        //
        //         // close window when user clicks outside of it
        //
        //         MenuBarExtraUtils.setPresented(for: .index(index), state: false)
        //
        //         #if DEBUG
        //         print("Global mouse-down events monitor: Setting isMenuPresented to false")
        //         #endif
        //
        //         isMenuPresented = false
        //     }
        // }
        
        observerContainer.setupWindowObservers(
            index: index,
            didBecomeKey: { window in
                #if DEBUG
                print("MenuBarExtra index \(index) drop-down window did become key.")
                #endif
                
                MenuBarExtraUtils.setKnownPresented(for: .index(index), state: true)
                isMenuPresented = true
            },
            didResignKey: { window in
                #if DEBUG
                print("MenuBarExtra index \(index) drop-down window did resign as key.")
                #endif
                
                // it's possible for a window to resign key without actually closing, so let's
                // close it as a failsafe.
                if window.isVisible {
                    #if DEBUG
                    print("Closing MenuBarExtra index \(index) drop-down window as a result of it resigning as key.")
                    #endif
                    
                    window.close()
                }
                
                MenuBarExtraUtils.setKnownPresented(for: .index(index), state: false)
                isMenuPresented = false
            }
        )
        
        return 0
    }
    
    // MARK: Observers
    
    @StateObject private var observerContainer = ObserverContainer()
    
    private class ObserverContainer: ObservableObject {
        private var statusItemIntrospectionSetup: Bool = false
        private var observer: NSStatusItem.ButtonStateObserver?
        private var eventsMonitor: Any?
        private var windowDidBecomeKeyObserver: AnyCancellable?
        private var windowDidResignKeyObserver: AnyCancellable?
        
        init() { }
        
        func setupStatusItemIntrospection(
            _ block: @escaping () -> Void
        ) {
            guard !statusItemIntrospectionSetup else { return }
            // run async so that it can execute after SwiftUI sets up the NSStatusItem
            DispatchQueue.main.async {
                block()
            }
        }
        
        func setupStatusItemButtonStateObserver(
            _ block: @escaping () -> NSStatusItem.ButtonStateObserver?
        ) {
            // run async so that it can execute after SwiftUI sets up the NSStatusItem
            DispatchQueue.main.async { [weak self] in
                self?.observer = block()
            }
        }
        
        func setupGlobalMouseDownMonitor(
            _ block: @escaping () -> Any?
        ) {
            // run async so that it can execute after SwiftUI sets up the NSStatusItem
            DispatchQueue.main.async { [weak self] in
                // tear down old monitor, if one exists
                if let eventsMonitor = self?.eventsMonitor {
                    NSEvent.removeMonitor(eventsMonitor)
                }
                
                self?.eventsMonitor = block()
            }
        }
        
        func setupWindowObservers(
            index: Int,
            didBecomeKey didBecomeKeyBlock: @escaping (_ window: NSWindow) -> Void,
            didResignKey didResignKeyBlock: @escaping (_ window: NSWindow) -> Void
        ) {
            // run async so that it can execute after SwiftUI sets up the NSStatusItem
            DispatchQueue.main.async { [weak self] in
                self?.windowDidBecomeKeyObserver = MenuBarExtraUtils.newWindowObserver(
                    index: index,
                    for: NSWindow.didBecomeKeyNotification
                ) { window in didBecomeKeyBlock(window) }
                
                self?.windowDidResignKeyObserver = MenuBarExtraUtils.newWindowObserver(
                    index: index,
                    for: NSWindow.didResignKeyNotification
                ) { window in didResignKeyBlock(window) }
                
            }
        }
    }
}

#endif
