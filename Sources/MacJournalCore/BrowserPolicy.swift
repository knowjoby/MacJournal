import Foundation

public enum BrowserPolicy {
    private static let supported: Set<String> = ["com.google.Chrome", "com.google.Chrome.canary", "com.google.Chrome.beta", "org.chromium.Chromium", "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly", "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev", "com.microsoft.edgemac.Canary", "com.vivaldi.Vivaldi", "com.operasoftware.Opera"]
    public static func capturesMediaTitle(_ rawURL: String) -> Bool {
        guard let url = URL(string: rawURL), let host = url.host?.lowercased(),
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return false }
        return host == "netflix.com" || host.hasSuffix(".netflix.com") || host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be" ||
            host == "primevideo.com" || host.hasSuffix(".primevideo.com") ||
            (["amazon.com", "amazon.co.uk", "amazon.in", "amazon.de", "amazon.co.jp"].contains { host == $0 || host == "www." + $0 } &&
             (url.path.hasPrefix("/gp/video/") || url.path.hasPrefix("/Amazon-Video/")))
    }
    public static func isNetflixWatch(_ raw: String) -> Bool {
        guard let url = URL(string: raw), let host = url.host?.lowercased() else { return false }
        return (host == "netflix.com" || host.hasSuffix(".netflix.com")) && url.path.hasPrefix("/watch/")
    }
    public static let netflixTitleJavaScript = """
    (() => {
      if (!(location.hostname === 'netflix.com' || location.hostname.endsWith('.netflix.com')) || !location.pathname.startsWith('/watch/')) return '';
      const key = '__macJournalNetflixTitleV1';
      let state = window[key];
      if (!state) {
        state = {path: '', title: ''};
        state.read = () => {
          if (state.path !== location.pathname) { state.path = location.pathname; state.title = ''; }
          const overlay = document.querySelector('[data-uia="evidence-overlay"]');
          const headings = overlay ? ['h2', 'h4', 'h3'].map(s => overlay.querySelector(s)?.textContent?.trim()).filter(Boolean) : [];
          const controls = document.querySelector('[data-uia="video-title"], .video-title');
          const controlParts = controls ? Array.from(controls.querySelectorAll('h4, span')).map(el => el.textContent?.trim()).filter(Boolean) : [];
          const media = navigator.mediaSession?.metadata;
          const mediaTitle = media?.title && media.title.trim().toLowerCase() !== 'netflix' ? [media.title, media.artist, media.album].filter(Boolean).join(' — ') : '';
          const title = headings.length ? headings.join(' — ') : (controlParts.join(' — ') || (controls?.textContent || '').trim() || mediaTitle);
          if (title) state.title = 'Netflix · ' + title.replace(/\\s+/g, ' ').slice(0, 500);
        };
        state.observer = new MutationObserver(() => state.read());
        state.observer.observe(document.documentElement, {childList: true, subtree: true, characterData: true});
        window[key] = state;
      }
      state.read();
      return state.title;
    })()
    """
    public static func isSubstackArticle(_ raw: String) -> Bool {
        guard let url = URL(string: raw), let host = url.host?.lowercased(),
              host == "substack.com" || host.hasSuffix(".substack.com") else { return false }
        return url.path.hasPrefix("/p/") || url.path.hasPrefix("/home/post/p-")
    }
    public static let substackTitleJavaScript = """
    (() => {
      if (!(location.hostname === 'substack.com' || location.hostname.endsWith('.substack.com'))) return '';
      const reader = location.pathname.startsWith('/home/post/p-');
      if (!reader && !location.pathname.startsWith('/p/')) return '';
      const selectors = reader ? ['a[href*="/p/"][class*="font-display"]'] : ['h1.post-title', 'article h1', 'h1'];
      for (const selector of selectors) {
        for (const element of document.querySelectorAll(selector)) {
          if (!element.getClientRects().length) continue;
          const title = element.textContent?.trim();
          if (title) return title.replace(/\\s+/g, ' ').slice(0, 500);
        }
      }
      return '';
    })()
    """
    public static func isAmazonStore(_ raw: String) -> Bool {
        guard let url = URL(string: raw), let host = url.host?.lowercased() else { return false }
        let domains = ["amazon.com", "amazon.in", "amazon.co.uk", "amazon.de", "amazon.fr", "amazon.it", "amazon.es", "amazon.ca", "amazon.com.au", "amazon.co.jp", "amazon.com.br", "amazon.com.mx", "amazon.ae", "amazon.sa", "amazon.nl", "amazon.se", "amazon.pl", "amazon.sg"]
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
    public static func isAmazonProduct(_ raw: String) -> Bool {
        guard isAmazonStore(raw), let url = URL(string: raw) else { return false }
        return url.path.contains("/dp/") || url.path.contains("/gp/product/")
    }
    public static let pageTitleJavaScript = """
    (() => {
      const host = location.hostname.toLowerCase();
      const matches = domain => host === domain || host.endsWith('.' + domain);
      const visibleText = selector => {
        for (const candidate of selector.split(',')) {
          for (const node of document.querySelectorAll(candidate.trim())) {
            if (!node.getClientRects().length) continue;
            const text = node.textContent?.trim();
            if (text) return text;
          }
        }
        return '';
      };
      let title = '';
      if (matches('reddit.com') && location.pathname.includes('/comments/')) {
        const postID = location.pathname.match(/\\/comments\\/([a-z0-9]+)/i)?.[1];
        const modern = document.querySelector('shreddit-post');
        if (modern && postID) {
          title = visibleText('#post-title-t3_' + postID);
          if (!title) return '__MACJOURNAL_REDDIT_LOADING__';
        } else {
          title = visibleText('h1[slot="title"], [data-testid="post-container"] h1, .top-matter a.title, h1');
        }
      } else if (/^(?:[a-z0-9-]+\\.)*amazon\\.(?:com|in|co\\.uk|de|fr|it|es|ca|com\\.au|co\\.jp|com\\.br|com\\.mx|ae|sa|nl|se|pl|sg)$/.test(host) && /\\/(?:dp|gp\\/product)\\//.test(location.pathname)) {
        title = visibleText('#productTitle, #ebooksProductTitle');
      } else if (!['netflix.com', 'youtube.com', 'youtu.be', 'primevideo.com', 'substack.com'].some(matches)) {
        title = visibleText('h1.post-title, article h1, [itemtype="https://schema.org/BlogPosting"] h1, [itemtype="http://schema.org/BlogPosting"] h1');
        if (!title && document.querySelector('meta[property="og:type"]')?.content === 'article') {
          title = visibleText('main h1, h1') || document.querySelector('meta[property="og:title"]')?.content || '';
        }
      }
      return title.replace(/\\s+/g, ' ').trim().slice(0, 500);
    })()
    """
    public static func requiresPermissionRetry(_ errorCode: Int) -> Bool {
        // Only explicit TCC denial needs a manual permission change. Timeouts,
        // browser navigation and temporarily missing windows must self-recover.
        errorCode == -1743
    }
    public static func metadataScript(_ bundle: String) -> String? {
        guard supportsURLCapture(bundle) else { return nil }
        let pageJS = pageTitleJavaScript.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: " ")
        let substackJS = substackTitleJavaScript.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: " ")
        let js = netflixTitleJavaScript.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: " ")
        return """
        with timeout of 2 seconds
        tell application id "\(bundle)"
            if (count of windows) = 0 then return ""
            set captureWindowID to id of front window
            set captureWindow to window id captureWindowID
            if mode of captureWindow is not "normal" then return ""
            set captureTabID to id of active tab of captureWindow
            set captureTab to tab id captureTabID of captureWindow
            set tabURL to URL of captureTab
            set tabTitle to title of captureTab
            set titleStatus to "tab"
            if tabURL starts with "https://www.netflix.com/watch/" or tabURL starts with "https://netflix.com/watch/" then
                try
                    set playerTitle to execute captureTab javascript "\(js)"
                    if playerTitle is not missing value and playerTitle is not "" then
                        set tabTitle to playerTitle
                        set titleStatus to "player"
                    else
                        set titleStatus to "waiting-player"
                    end if
                on error errorMessage number errorCode
                    set titleStatus to "player-access-disabled: " & errorCode & " " & errorMessage
                end try
            end if
            if tabURL starts with "https://substack.com/home/post/" or tabURL contains ".substack.com/p/" or tabURL starts with "https://substack.com/p/" then
                try
                    set articleTitle to execute captureTab javascript "\(substackJS)"
                    if articleTitle is not missing value and articleTitle is not "" then
                        set tabTitle to articleTitle
                        set titleStatus to "article"
                    end if
                on error
                    set titleStatus to "article-tab-fallback"
                end try
            end if
            if titleStatus is "tab" and (tabURL starts with "https://" or tabURL starts with "http://") then
                try
                    set pageTitle to execute captureTab javascript "\(pageJS)"
                    if pageTitle is "__MACJOURNAL_REDDIT_LOADING__" then return ""
                    if pageTitle is not missing value and pageTitle is not "" then
                        set tabTitle to pageTitle
                        set titleStatus to "page-heading"
                    end if
                on error
                    set titleStatus to "page-tab-fallback"
                end try
            end if
            if id of front window is not captureWindowID then return ""
            if mode of captureWindow is not "normal" then return ""
            if id of active tab of captureWindow is not captureTabID then return ""
            if URL of captureTab is not tabURL then return ""
            return {tabURL, tabTitle, titleStatus}
        end tell
        end timeout
        """
    }
    public static func supportsURLCapture(_ bundle: String) -> Bool { supported.contains(bundle) }
    public static func unsupportedBrowser(_ bundle: String) -> Bool {
        ["com.apple.Safari", "org.mozilla.firefox", "company.thebrowser", "com.kagi", "net.imput.helium", "app.zen-browser"].contains { bundle.hasPrefix($0) }
    }
}
