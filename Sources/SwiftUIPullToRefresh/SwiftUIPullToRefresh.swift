import SwiftUI

// There are two type of positioning views - one that scrolls with the content,
// and one that stays fixed
private enum PositionType {
  case fixed, moving
}

// This struct is the currency of the Preferences, and has a type
// (fixed or moving) and the actual Y-axis value.
// It's Equatable because Swift requires it to be.
private struct Position: Equatable {
  let type: PositionType
  let y: CGFloat
}

// This might seem weird, but it's necessary due to the funny nature of
// how Preferences work. We can't just store the last position and merge
// it with the next one - instead we have a queue of all the latest positions.
private struct PositionPreferenceKey: PreferenceKey {
  typealias Value = [Position]

  static var defaultValue = [Position]()

  static func reduce(value: inout [Position], nextValue: () -> [Position]) {
    value.append(contentsOf: nextValue())
  }
}

private struct PositionIndicator: View {
  let type: PositionType

  var body: some View {
    GeometryReader { proxy in
        // the View itself is an invisible Shape that fills as much as possible
        Color.clear
          // Compute the top Y position and emit it to the Preferences queue
          .preference(key: PositionPreferenceKey.self, value: [Position(type: type, y: proxy.frame(in: .global).minY)])
     }
  }
}

// Callback that'll trigger once refreshing is done
public typealias RefreshComplete = () -> Void
// The actual refresh action that's called once refreshing starts. It has the
// RefreshComplete callback to let the refresh action let the View know
// once it's done refreshing.
public typealias OnRefresh = (@escaping RefreshComplete) -> Void

// The offset threshold. 50 is a good number, but you can play
// with it to your liking.
private let THRESHOLD: CGFloat = 50

// Tracks the state of the RefreshableScrollView - it's either:
// 1. waiting for a scroll to happen
// 2. has been primed by pulling down beyond THRESHOLD
// 3. is doing the refreshing.
public enum RefreshState {
  case waiting, primed, loading
}

// ViewBuilder for the custom progress View, that may render itself
// based on the current RefreshState.
public typealias RefreshProgressBuilder<Progress: View> = (RefreshState) -> Progress

public struct RefreshableScrollView<Progress, Content>: View where Progress: View, Content: View {
  let onRefresh: OnRefresh // the refreshing action
  let progress: RefreshProgressBuilder<Progress> // custom progress view
  let content: () -> Content // the ScrollView content
  let showsIndicators: Bool

  @State private var state = RefreshState.waiting // the current state

  // We use a custom constructor to allow for usage of a @ViewBuilder for the content
  public init(showsIndicators: Bool,
              onRefresh: @escaping OnRefresh,
              @ViewBuilder progress: @escaping RefreshProgressBuilder<Progress>,
              @ViewBuilder content: @escaping () -> Content) {
    self.onRefresh = onRefresh
    self.progress = progress
    self.content = content
    self.showsIndicators = showsIndicators
  }

  public var body: some View {
    // The root view is a regular ScrollView
    ScrollView(showsIndicators: showsIndicators) {
      // The ZStack allows us to position the PositionIndicator,
      // the content and the loading view, all on top of each other.
      ZStack(alignment: .top) {
        // The moving positioning indicator, that sits at the top
        // of the ScrollView and scrolls down with the content
        PositionIndicator(type: .moving)
          .frame(height: 0)

         // Your ScrollView content. If we're loading, we want
         // to keep it below the loading view, hence the alignmentGuide.
         content()
           .alignmentGuide(.top, computeValue: { _ in
             (state == .loading) ? -THRESHOLD : 0
            })

          // The loading view. It's offset to the top of the content unless we're loading.
          ZStack {
            Rectangle()
              .foregroundColor(.white)
              .frame(height: THRESHOLD)
            progress(state)
          }.offset(y: (state == .loading) ? 0 : -THRESHOLD)
        }
      }
      // Put a fixed PositionIndicator in the background so that we have
      // a reference point to compute the scroll offset.
      .background(PositionIndicator(type: .fixed))
      // Once the scrolling offset changes, we want to see if there should
      // be a state change.
      .onPreferenceChange(PositionPreferenceKey.self) { values in
        if state != .loading { // If we're already loading, ignore everything
          // Map the preference change action to the UI thread
          DispatchQueue.main.async {
            // Compute the offset between the moving and fixed PositionIndicators
            let movingY = values.first { $0.type == .moving }?.y ?? 0
            let fixedY = values.first { $0.type == .fixed }?.y ?? 0
            let offset = movingY - fixedY

            // If the user pulled down below the threshold, prime the view
            if offset > THRESHOLD && state == .waiting {
              state = .primed

            // If the view is primed and we've crossed the threshold again on the
            // way back, trigger the refresh
            } else if offset < THRESHOLD && state == .primed {
              state = .loading
              onRefresh { // trigger the refreshing callback
                // once refreshing is done, smoothly move the loading view
                // back to the offset position
                withAnimation {
                  self.state = .waiting
                }
              }
            }
          }
        }
      }
  }
}

// Extension that uses default RefreshActivityIndicator so that you don't have to
// specify it every time.
public extension RefreshableScrollView where Progress == RefreshActivityIndicator {
    init(showsIndicators: Bool = true,
         onRefresh: @escaping OnRefresh,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(showsIndicators: showsIndicators,
                  onRefresh: onRefresh,
                  progress: { state in
                    RefreshActivityIndicator(isAnimating: state == .loading) {
                        $0.hidesWhenStopped = false
                    }
                 },
                 content: content)
    }
}

// Wraps a UIActivityIndicatorView as a loading spinner that works on all SwiftUI versions.
public struct RefreshActivityIndicator: UIViewRepresentable {
  public typealias UIView = UIActivityIndicatorView
  public var isAnimating: Bool = true
  public var configuration = { (indicator: UIView) in }

  public init(isAnimating: Bool, configuration: ((UIView) -> Void)? = nil) {
    self.isAnimating = isAnimating
    if let configuration = configuration {
      self.configuration = configuration
    }
  }

  public func makeUIView(context: UIViewRepresentableContext<Self>) -> UIView {
    UIView()
  }

  public func updateUIView(_ uiView: UIView, context: UIViewRepresentableContext<Self>) {
    isAnimating ? uiView.startAnimating() : uiView.stopAnimating()
    configuration(uiView)
  }
}

#if compiler(>=5.5)
// Allows using RefreshableScrollView with an async block.
@available(iOS 15.0, *)
public extension RefreshableScrollView {
    init(action: @escaping @Sendable () async -> Void,
         @ViewBuilder progress: @escaping RefreshProgressBuilder<Progress>,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(
            onRefresh: { refreshComplete in
                Task {
                    await action()
                    refreshComplete()
                }
            },
            progress: progress,
            content: content)
    }
}
#endif

public struct RefreshableCompat<Progress>: ViewModifier where Progress: View {
    private let onRefresh: OnRefresh
    private let progress: RefreshProgressBuilder<Progress>
    
    public init(onRefresh: @escaping OnRefresh,
                @ViewBuilder progress: @escaping RefreshProgressBuilder<Progress>) {
        self.onRefresh = onRefresh
        self.progress = progress
    }
    
    public func body(content: Content) -> some View {
        RefreshableScrollView(onRefresh: onRefresh, progress: progress) {
            content
        }
    }
}

#if compiler(>=5.5)
@available(iOS 15.0, *)
public extension List {
    @ViewBuilder func refreshableCompat<Progress: View>(onRefresh: @escaping OnRefresh,
                                                        @ViewBuilder progress: @escaping RefreshProgressBuilder<Progress>) -> some View {
        if #available(iOS 15.0, macOS 12.0, *) {
            self.refreshable {
                await withCheckedContinuation { cont in
                    onRefresh {
                        cont.resume()
                    }
                }
            }
        } else {
            self.modifier(RefreshableCompat(onRefresh: onRefresh, progress: progress))
        }
    }
}
#endif

public extension View {
    @ViewBuilder func refreshableCompat<Progress: View>(onRefresh: @escaping OnRefresh,
                                                        @ViewBuilder progress: @escaping RefreshProgressBuilder<Progress>) -> some View {
        self.modifier(RefreshableCompat(onRefresh: onRefresh, progress: progress))
    }
}

struct TestView: View {
  @State private var now = Date()

  var body: some View {
     RefreshableScrollView(onRefresh: { done in
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
          self.now = Date()
          done()
        }
      }) {
        VStack {
          ForEach(1..<20) {
            Text("\(Calendar.current.date(byAdding: .hour, value: $0, to: now)!)")
               .padding(.bottom, 10)
           }
         }.padding()
       }
     }
}

struct TestViewWithCustomProgress: View {
    @State private var now = Date()

    var body: some View {
       RefreshableScrollView(onRefresh: { done in
          DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.now = Date()
            done()
          }
        },
                             progress: { state in
           if state == .waiting {
               Text("Pull me down...")
           } else if state == .primed {
               Text("Now release!")
           } else {
               Text("Working...")
           }
       }
       ) {
          VStack {
            ForEach(1..<20) {
              Text("\(Calendar.current.date(byAdding: .hour, value: $0, to: now)!)")
                 .padding(.bottom, 10)
             }
           }.padding()
         }
       }
  }

#if compiler(>=5.5)
@available(iOS 15, *)
struct TestViewWithAsync: View {
  @State private var now = Date()

  var body: some View {
     RefreshableScrollView(action: {
         await Task.sleep(3_000_000_000)
         now = Date()
     }, progress: { state in
         RefreshActivityIndicator(isAnimating: state == .loading) {
             $0.hidesWhenStopped = false
         }
     }) {
        VStack {
          ForEach(1..<20) {
            Text("\(Calendar.current.date(byAdding: .hour, value: $0, to: now)!)")
               .padding(.bottom, 10)
           }
         }.padding()
       }
     }
}
#endif

struct TestViewCompat: View {
    @State private var now = Date()

  var body: some View {
      VStack {
          ForEach(1..<20) {
          Text("\(Calendar.current.date(byAdding: .hour, value: $0, to: now)!)")
            .padding(.bottom, 10)
        }
      }
      .refreshableCompat { done in
          DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.now = Date()
            done()
          }
      } progress: { state in
          RefreshActivityIndicator(isAnimating: state == .loading) {
              $0.hidesWhenStopped = false
          }
      }

   }
}

struct TestView_Previews: PreviewProvider {
    static var previews: some View {
        TestView()
    }
}

struct TestViewWithCustomProgress_Previews: PreviewProvider {
    static var previews: some View {
        TestViewWithCustomProgress()
    }
}

#if compiler(>=5.5)
@available(iOS 15, *)
struct TestViewWithAsync_Previews: PreviewProvider {
    static var previews: some View {
        TestViewWithAsync()
    }
}

struct TestViewCompat_Previews: PreviewProvider {
    static var previews: some View {
        TestViewCompat()
    }
}
#endif
