Receiver VR (experimental)
==========================

Receiver VR lets a standalone headset display and control a Mac without an app
installation on the headset. It runs in the headset browser as a large virtual
screen and uses only the local Wi-Fi network.

Quick start
-----------

1. Connect the headset and the Sender Mac to the same Wi-Fi network.
2. In TargetBridge on the Mac, open **Settings > Add-ons**.
3. Enable **Receiver VR**, then click **Start VR Receiver**.
4. In the headset browser, scan the QR code shown in TargetBridge.
5. Aim at the streamed desktop and press to click. Use the on-screen arrows and
   scroll buttons if the browser does not offer controller axes to web pages.

Permissions and privacy
-----------------------

The Sender needs:

- Screen Recording, to provide the desktop image.
- Accessibility, to apply mouse clicks and scrolling sent by the browser.

The Receiver VR server only listens on the local network while it is running.
It does not use a TargetBridge cloud service and does not upload screen images.
Each start creates a new pairing code inside the QR link; requests without that
code are rejected.

Limitations in the first version
--------------------------------

- The display is a browser panel in the headset, not a native stereoscopic app.
- Audio is not relayed.
- Performance is tuned for compatibility rather than 5K quality; use a strong
  local Wi-Fi signal.
- Browser support for physical controller axes and hand tracking differs by
  headset and software version. Pointer/tap interaction and the on-screen
  controls are the fallback.
- Quest 1 support is experimental until it has been verified on hardware.

Troubleshooting
---------------

- If the QR code opens nothing, confirm both devices use the same Wi-Fi network
  and allow TargetBridge through the macOS firewall when asked.
- If the desktop is black, re-check Screen Recording for TargetBridge.
- If the desktop is visible but does not respond, enable Accessibility for
  TargetBridge and restart Receiver VR.
