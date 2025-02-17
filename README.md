# SwiftUIPullToRefresh

Pull to refresh is a common UI pattern, supported in UIKit via UIRefreshControl. (Un)surprisingly, it's also unavailable in SwiftUI prior to version 3, and even then [it's a bit lackluster](https://swiftuirecipes.com/blog/pull-to-refresh-with-swiftui-scrollview#drawbacks).

This package contains a component - `RefreshableScrollView`  - that enables this functionality with **any `ScrollView`**. It also **doesn't rely on `UIViewRepresentable`**, and works with **any iOS version**. The end result looks like this:

![in action](https://swiftuirecipes.com/user/pages/01.blog/pull-to-refresh-with-swiftui-scrollview/ezgif-4-bf1673b185d4.gif)

## Features

* Works on any `ScrollView`.
* Customizable progress indicator, with a default `RefreshActivityIndicator` spinner that works on any SwiftUI version.
* Specify refresh operation and choose when it ends.
* Support for Swift 5.5 `async` blocks.
* Compatibility `refreshCompat` modifier to deliver a drop-in replacement for iOS 15 `refreshable`. 

## Installation

This component is distrubuted as a **Swift package**. Just add this URL to your package list:

```text
https://github.com/globulus/swiftui-pull-to-refresh
```

## Sample usage

### Bread & butter

```swift
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
}
```

### Custom progress view

```swift
RefreshableScrollView(onRefresh: { done in
  DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
    self.now = Date()
    done()
  }
},
progress: { state in // HERE
   if state == .waiting {
       Text("Pull me down...")
   } else if state == .primed {
       Text("Now release!")
   } else {
       Text("Working...")
   }
}) {
  VStack {
    ForEach(1..<20) {
      Text("\(Calendar.current.date(byAdding: .hour, value: $0, to: now)!)")
         .padding(.bottom, 10)
     }
   }.padding()
}
```

### Using async block

```swift
 RefreshableScrollView(action: { // HERE
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
```

### Compatibility mode

```swift
  VStack {
      ForEach(1..<20) {
      Text("\(Calendar.current.date(byAdding: .hour, value: $0, to: now)!)")
        .padding(.bottom, 10)
    }
  }
  .refreshableCompat { done in // HERE
      DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
        self.now = Date()
        done()
      }
  } progress: { state in
      RefreshActivityIndicator(isAnimating: state == .loading) {
          $0.hidesWhenStopped = false
      }
  }
```

## Recipe

Check out [this recipe](https://swiftuirecipes.com/blog/pull-to-refresh-with-swiftui-scrollview) for in-depth description of the component and its code. Check out [SwiftUIRecipes.com](https://swiftuirecipes.com) for more **SwiftUI recipes**!

