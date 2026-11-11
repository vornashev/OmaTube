import QtQuick
import QtTest
import "../../ui" as OmaTube

Item {
  Window {
    id: testWindow
    width: 400
    height: 400
    visible: false

    Item {
      id: container
      anchors.fill: parent
      OmaTube.Equalizer { id: equalizer }
      OmaTube.SkeletonList { id: skeleton; width: 300; rowCount: 2 }
      OmaTube.IconButton { id: loadingButton; spinning: true }
      OmaTube.Icon {
        id: spinner
        RotationAnimator on rotation {
          id: spin
          running: spinner.animationVisible
          from: 0
          to: 360
          duration: 900
          loops: Animation.Infinite
        }
      }
    }
  }

  SignalSpy { id: eqSpy; signalName: "levelChanged" }
  SignalSpy { id: shimmerSpy; signalName: "xChanged" }
  SignalSpy { id: buttonSpy; signalName: "rotationChanged" }

  TestCase {
    name: "IdleAnimations"
    when: windowShown

    function findItem(item, predicate) {
      if (predicate(item)) return item
      for (var i = 0; i < item.children.length; ++i) {
        var found = findItem(item.children[i], predicate)
        if (found) return found
      }
      return null
    }

    function assertStopped() {
      // Let a stop/reset complete before watching for further changes.
      wait(50)
      eqSpy.clear()
      shimmerSpy.clear()
      buttonSpy.clear()
      wait(200)
      compare(eqSpy.count, 0)
      compare(shimmerSpy.count, 0)
      compare(buttonSpy.count, 0)
      compare(spin.running, false)
    }

    function assertRunning() {
      eqSpy.clear()
      shimmerSpy.clear()
      buttonSpy.clear()
      tryVerify(function() { return eqSpy.count > 0 && shimmerSpy.count > 0 && buttonSpy.count > 0 })
      compare(spin.running, true)
    }

    function test_visibility_lifecycle() {
      eqSpy.target = findItem(equalizer, function(item) { return item.level !== undefined })
      shimmerSpy.target = findItem(skeleton, function(item) { return item.rotation === 8 })
      buttonSpy.target = findItem(loadingButton, function(item) { return item.animationVisible !== undefined })
      verify(eqSpy.valid)
      verify(shimmerSpy.valid)
      verify(buttonSpy.valid)

      // A hidden window can still contain items whose visible property is true.
      verify(equalizer.visible)
      assertStopped()
      testWindow.visible = true
      assertRunning()

      equalizer.visible = false
      skeleton.visible = false
      spinner.visible = false
      loadingButton.visible = false
      assertStopped()
      equalizer.visible = true
      skeleton.visible = true
      spinner.visible = true
      loadingButton.visible = true
      assertRunning()

      container.visible = false
      assertStopped()
      container.visible = true
      assertRunning()

      testWindow.visible = false
      assertStopped()
      testWindow.visible = true
      assertRunning()

      equalizer.running = false
      wait(50)
      eqSpy.clear()
      wait(200)
      compare(eqSpy.count, 0)
      equalizer.running = true
      tryVerify(function() { return eqSpy.count > 0 })
      testWindow.visible = false
    }
  }
}
