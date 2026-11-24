#!/usr/bin/env python3
# Part of Golem: zones, rooms, the Gate and the browser; MAP.md sections 5.2, 5.3.
"""golem-browser: Golem's only browser. It reaches the internet through the Gate, and nothing stays.

  golem-browser [address or words]

  Ctrl+L      type an address, or words to search (DuckDuckGo, the simple version)
  Alt+←  Alt+→  back, forward          Ctrl+R / F5  reload        Ctrl+T  a new window
  Ctrl+J      JavaScript on/off for this site (off everywhere until you turn it on; remembered)
  Ctrl+Plus / Ctrl+Minus  zoom         Ctrl+F  find on the page   Esc  stop / leave the bar
  Ctrl+W      close

* Every request goes through the Gate (127.0.0.1:3128): the Gate asks you about each new site.
* No history, no cookies, no cache kept: closing the window forgets everything.
* No pop-up windows. Downloads go to ~/Downloads in its own zone folder, and are written in the truth log.
"""
import json
import os
import subprocess
import sys
from urllib.parse import quote_plus, urlparse

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("WebKit", "6.0")
from gi.repository import Gdk, GLib, Gtk, WebKit  # noqa: E402

GATE = "http://127.0.0.1:3128"
JS_FILE = os.path.expanduser("~/.golem-browser-js.json")     # sites where I turned JavaScript on
CSS = b"""
window, headerbar, entry { background: #000; color: #fff; }
entry { border: 1px solid #555; border-radius: 0; font-family: "Golem Runes", serif; font-size: 13px; }
label.state { color: #8c8c8c; font-size: 11px; margin: 0 8px; }
"""


def log(msg):
    try:
        subprocess.run(["logger", "-t", "zone", "Browser: " + msg], check=False, timeout=3)
    except OSError:
        pass


def js_sites():
    try:
        with open(JS_FILE) as f:
            return set(json.load(f))
    except (OSError, ValueError):
        return set()


def save_js(sites):
    with open(JS_FILE, "w") as f:
        json.dump(sorted(sites), f)


def to_url(text):
    t = text.strip()
    if not t:
        return None
    if "://" in t:
        return t
    if " " not in t and "." in t:
        return "https://" + t
    return "https://html.duckduckgo.com/html/?q=" + quote_plus(t)


class Window:
    def __init__(self, app, session, url):
        self.app, self.session = app, session
        self.view = WebKit.WebView(network_session=session)
        st = self.view.get_settings()
        st.set_enable_javascript(False)
        st.set_javascript_can_open_windows_automatically(False)
        st.set_enable_developer_extras(False)
        self.view.connect("load-changed", self.loaded)
        self.view.connect("create", lambda *a: None)              # no pop-up windows
        self.view.connect("decide-policy", self.decide)
        self.entry = Gtk.Entry(hexpand=True, placeholder_text="an address, or words to search")
        self.entry.connect("activate", lambda e: self.go(e.get_text()))
        self.state = Gtk.Label(label="")
        self.state.add_css_class("state")
        bar = Gtk.Box(spacing=0)
        bar.append(self.entry)
        bar.append(self.state)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.append(bar)
        box.append(self.view)
        self.view.set_vexpand(True)
        self.win = Gtk.ApplicationWindow(application=app, title="golem-browser")
        self.win.set_default_size(1100, 750)
        self.win.set_child(box)
        keys = Gtk.EventControllerKey()
        keys.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        keys.connect("key-pressed", self.key)
        self.win.add_controller(keys)
        self.win.present()
        if url:
            self.go(url)
        else:
            self.entry.grab_focus()

    def site(self):
        u = urlparse(self.view.get_uri() or "")
        return u.hostname or ""

    def go(self, text):
        url = to_url(text)
        if not url:
            return
        host = urlparse(url).hostname or ""
        self.view.get_settings().set_enable_javascript(host in js_sites())
        self.view.load_uri(url)
        self.view.grab_focus()

    def loaded(self, view, event):
        if event == WebKit.LoadEvent.COMMITTED:
            self.entry.set_text(view.get_uri() or "")
            js = view.get_settings().get_enable_javascript()
            self.state.set_label("JS ON" if js else "JS OFF")
            self.win.set_title((view.get_title() or self.site()) + "  ·  golem-browser")
        elif event == WebKit.LoadEvent.FINISHED:
            self.win.set_title((view.get_title() or self.site()) + "  ·  golem-browser")

    def decide(self, view, decision, kind):
        if kind == WebKit.PolicyDecisionType.NAVIGATION_ACTION:
            host = urlparse(decision.get_navigation_action().get_request().get_uri()).hostname or ""
            view.get_settings().set_enable_javascript(host in js_sites())
        elif kind == WebKit.PolicyDecisionType.RESPONSE and not decision.is_mime_type_supported():
            decision.download()
            return True
        return False

    def key(self, ctrl, keyval, code, state):
        c = bool(state & Gdk.ModifierType.CONTROL_MASK)
        a = bool(state & Gdk.ModifierType.ALT_MASK)
        v = self.view
        if c and keyval == Gdk.KEY_l:
            self.entry.grab_focus()
            self.entry.select_region(0, -1)
        elif (a and keyval == Gdk.KEY_Left) or keyval == Gdk.KEY_Back:
            v.go_back()
        elif (a and keyval == Gdk.KEY_Right) or keyval == Gdk.KEY_Forward:
            v.go_forward()
        elif (c and keyval == Gdk.KEY_r) or keyval == Gdk.KEY_F5:
            v.reload()
        elif c and keyval == Gdk.KEY_t:
            Window(self.app, self.session, None)
        elif c and keyval == Gdk.KEY_w:
            self.win.close()
        elif c and keyval in (Gdk.KEY_plus, Gdk.KEY_equal):
            v.set_zoom_level(v.get_zoom_level() * 1.1)
        elif c and keyval == Gdk.KEY_minus:
            v.set_zoom_level(v.get_zoom_level() / 1.1)
        elif c and keyval == Gdk.KEY_f:
            self.find()
        elif c and keyval == Gdk.KEY_j:
            site, sites = self.site(), js_sites()
            if not site:
                return True
            if site in sites:
                sites.discard(site)
            else:
                sites.add(site)
            save_js(sites)
            log(f"JavaScript {'ON' if site in sites else 'OFF'} for {site}")
            v.get_settings().set_enable_javascript(site in sites)
            v.reload()
        elif keyval == Gdk.KEY_Escape:
            v.stop_loading()
            v.grab_focus()
        else:
            return False
        return True

    def find(self):
        d = Gtk.Window(transient_for=self.win, modal=True, title="find")
        e = Gtk.Entry(placeholder_text="find on this page")
        fc = self.view.get_find_controller()
        flags = WebKit.FindOptions.CASE_INSENSITIVE | WebKit.FindOptions.WRAP_AROUND
        e.connect("activate", lambda x: fc.search(x.get_text(), flags, 100))
        d.set_child(e)
        d.present()


def main():
    url = " ".join(sys.argv[1:]) or None
    GLib.set_prgname("golem-browser")
    p = Gtk.CssProvider()
    try:
        p.load_from_string(CSS.decode())
    except AttributeError:
        p.load_from_data(CSS, len(CSS))
    app = Gtk.Application(application_id=None)

    def activate(app):
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), p, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        session = WebKit.NetworkSession.new_ephemeral()          # cookies, cache: gone when closed
        session.set_proxy_settings(WebKit.NetworkProxyMode.CUSTOM, WebKit.NetworkProxySettings.new(GATE, []))
        dl = os.path.expanduser("~/Downloads")
        os.makedirs(dl, exist_ok=True)

        def started(sess, download):
            def dest(d, name):
                path = os.path.join(dl, os.path.basename(name) or "download")
                d.set_destination(path)
                log(f"downloading {os.path.basename(path)}")
                return True
            download.connect("decide-destination", dest)
            download.connect("finished", lambda d: log(f"downloaded {os.path.basename(d.get_destination() or '')}"))
        session.connect("download-started", started)
        Window(app, session, url)

    app.connect("activate", activate)
    app.run([sys.argv[0]])


if __name__ == "__main__":
    main()
