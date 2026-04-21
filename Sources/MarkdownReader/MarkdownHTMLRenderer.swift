import Foundation

enum MarkdownHTMLRenderer {
    private static let markedScript: String = {
        guard
            let url = Bundle.module.url(forResource: "marked.min", withExtension: "js"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            return ""
        }
        return source
    }()

    static func fullDocumentHTML(
        markdownText: String,
        theme: ReaderTheme,
        fontSize: Double,
        lineWidth: Double
    ) -> String {
        let markdownJSON = jsonStringLiteral(markdownText)
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(baseCSS(theme: theme, fontSize: fontSize, lineWidth: lineWidth))
        </style>
        <script>
        \(markedScript)
        </script>
        </head>
        <body>
          <main id="markdown-root" class="markdown-body"></main>
          <script>
          const markdownSource = \(markdownJSON);

          function githubSlugBase(text) {
            const slug = text
              .trim()
              .toLowerCase()
              .replace(/`/g, '')
              .replace(/[^\\p{Letter}\\p{Number}\\u4e00-\\u9fff _-]+/gu, '')
              .replace(/\\s+/g, '-')
              .replace(/-+/g, '-')
              .replace(/^-+|-+$/g, '');
            return slug || 'section';
          }

          function buildHeadingIDs(headings) {
            const counts = new Map();
            headings.forEach((heading) => {
              if (heading.id) return;
              const explicitAnchor = heading.previousElementSibling;
              if (explicitAnchor && explicitAnchor.tagName === 'A' && explicitAnchor.id) {
                heading.id = explicitAnchor.id;
                return;
              }

              const base = githubSlugBase(heading.textContent || '');
              const count = counts.get(base) || 0;
              counts.set(base, count + 1);
              heading.id = count === 0 ? base : `${base}-${count}`;
            });
          }

          function jumpToAnchor(target) {
            if (!target) return false;
            const element = document.getElementById(target);
            if (!element) return false;
            element.scrollIntoView({ behavior: 'smooth', block: 'start' });
            history.replaceState(null, '', '#' + target);
            return true;
          }

          function maximumScrollTop() {
            const element = document.scrollingElement || document.documentElement || document.body;
            return Math.max(0, element.scrollHeight - window.innerHeight);
          }

          function currentScrollProgress() {
            const element = document.scrollingElement || document.documentElement || document.body;
            const maxScrollTop = maximumScrollTop();
            if (maxScrollTop <= 0) return 0;
            return Math.min(Math.max(element.scrollTop / maxScrollTop, 0), 1);
          }

          function reportScrollProgress() {
            if (window.__codexSuppressScrollSync) return;
            const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.readerScrollSync;
            if (!handler) return;
            handler.postMessage(currentScrollProgress());
          }

          function scheduleScrollReport() {
            if (window.__codexScrollReportPending) return;
            window.__codexScrollReportPending = true;
            window.requestAnimationFrame(() => {
              window.__codexScrollReportPending = false;
              reportScrollProgress();
            });
          }

          marked.setOptions({
            gfm: true,
            breaks: false,
            mangle: false,
            headerIds: false
          });

          const root = document.getElementById('markdown-root');
          root.innerHTML = marked.parse(markdownSource);

          const headings = root.querySelectorAll('h1, h2, h3, h4, h5, h6');
          buildHeadingIDs(headings);

          window.codexMarkdownJumpToAnchor = jumpToAnchor;
          window.codexSetScrollProgress = function(progress) {
            const element = document.scrollingElement || document.documentElement || document.body;
            const maxScrollTop = maximumScrollTop();
            const clamped = Math.min(Math.max(progress, 0), 1);
            const targetOffset = maxScrollTop * clamped;
            window.__codexSuppressScrollSync = true;
            element.scrollTop = targetOffset;
            document.documentElement.scrollTop = targetOffset;
            document.body.scrollTop = targetOffset;
            window.requestAnimationFrame(() => {
              reportScrollProgress();
              window.__codexSuppressScrollSync = false;
            });
            return currentScrollProgress();
          };

          root.querySelectorAll('a[href^="#"]').forEach((link) => {
            link.addEventListener('click', (event) => {
              const target = decodeURIComponent(link.getAttribute('href').slice(1));
              if (!jumpToAnchor(target)) return;
              event.preventDefault();
            });
          });

          window.addEventListener('scroll', scheduleScrollReport, { passive: true });
          window.requestAnimationFrame(reportScrollProgress);
          </script>
        </body>
        </html>
        """
    }

    static func fallbackHTML(
        markdownText: String,
        theme: ReaderTheme,
        fontSize: Double,
        lineWidth: Double
    ) -> String {
        let escaped = markdownText
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        return fullDocumentHTML(
            markdownText: "```text\\n\(escaped)\\n```",
            theme: theme,
            fontSize: fontSize,
            lineWidth: lineWidth
        )
    }

    static func emptyStateHTML(_ message: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, sans-serif;
          color: #6b7280;
          padding: 32px;
        }
        </style>
        </head>
        <body>\(message)</body>
        </html>
        """
    }

    private static func baseCSS(theme: ReaderTheme, fontSize: Double, lineWidth: Double) -> String {
        let palette = paletteForTheme(theme)
        let width = Int(lineWidth)
        let typeSize = Int(fontSize)

        return """
        :root {
          color-scheme: \(palette.colorScheme);
          --bg: \(palette.background);
          --fg: \(palette.foreground);
          --muted: \(palette.muted);
          --border: \(palette.border);
          --code-bg: \(palette.codeBackground);
          --quote: \(palette.quote);
          --link: \(palette.link);
          --max-width: \(width)px;
          --font-size: \(typeSize)px;
        }
        * { box-sizing: border-box; }
        html, body {
          margin: 0;
          padding: 0;
          background: var(--bg);
          color: var(--fg);
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
          font-size: var(--font-size);
          line-height: 1.65;
        }
        body { padding: 28px 32px 60px; }
        .markdown-body {
          max-width: var(--max-width);
          margin: 0 auto;
        }
        .markdown-body h1, .markdown-body h2, .markdown-body h3, .markdown-body h4, .markdown-body h5, .markdown-body h6 {
          line-height: 1.25;
          margin-top: 1.6em;
          margin-bottom: 0.6em;
        }
        .markdown-body h1, .markdown-body h2 {
          padding-bottom: 0.2em;
          border-bottom: 1px solid var(--border);
        }
        .markdown-body p, .markdown-body ul, .markdown-body ol, .markdown-body pre, .markdown-body table, .markdown-body blockquote, .markdown-body details {
          margin: 0.85em 0;
        }
        .markdown-body a {
          color: var(--link);
          text-decoration: none;
        }
        .markdown-body a:hover { text-decoration: underline; }
        .markdown-body hr {
          border: 0;
          border-top: 1px solid var(--border);
          margin: 2em 0;
        }
        .markdown-body code, .markdown-body pre, .markdown-body tt {
          font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
        }
        .markdown-body code {
          background: var(--code-bg);
          padding: 0.15em 0.35em;
          border-radius: 6px;
          font-size: 0.92em;
        }
        .markdown-body pre {
          background: var(--code-bg);
          padding: 14px 16px;
          border-radius: 12px;
          overflow-x: auto;
          border: 1px solid var(--border);
        }
        .markdown-body pre code {
          background: transparent;
          padding: 0;
          border-radius: 0;
        }
        .markdown-body blockquote {
          margin-left: 0;
          padding: 0.2em 1em;
          color: var(--muted);
          border-left: 4px solid var(--quote);
          background: color-mix(in srgb, var(--quote) 12%, transparent);
          border-radius: 0 8px 8px 0;
        }
        .markdown-body table {
          width: 100%;
          border-collapse: collapse;
          font-size: 0.95em;
        }
        .markdown-body th, .markdown-body td {
          border: 1px solid var(--border);
          padding: 10px 12px;
          text-align: left;
          vertical-align: top;
        }
        .markdown-body th {
          background: color-mix(in srgb, var(--code-bg) 65%, var(--bg));
        }
        .markdown-body img {
          max-width: 100%;
          height: auto;
        }
        .markdown-body a[id] {
          display: block;
          position: relative;
          top: -8px;
          visibility: hidden;
        }
        .markdown-body details {
          border: 1px solid var(--border);
          border-radius: 12px;
          padding: 0.75em 1em;
          background: color-mix(in srgb, var(--code-bg) 40%, var(--bg));
        }
        .markdown-body summary {
          cursor: pointer;
          font-weight: 600;
        }
        .markdown-body ul, .markdown-body ol {
          padding-left: 1.6em;
        }
        .markdown-body li + li {
          margin-top: 0.25em;
        }
        .markdown-body .task-list-item {
          list-style: none;
        }
        """
    }

    private static func jsonStringLiteral(_ string: String) -> String {
        let array = [string]
        guard
            let data = try? JSONSerialization.data(withJSONObject: array),
            let json = String(data: data, encoding: .utf8),
            json.count >= 2
        else {
            return "\"\""
        }
        return String(json.dropFirst().dropLast())
    }

    private static func paletteForTheme(_ theme: ReaderTheme) -> (
        colorScheme: String, background: String, foreground: String, muted: String,
        border: String, codeBackground: String, quote: String, link: String
    ) {
        switch theme {
        case .dark:
            return (
                "dark", "#111318", "#ECEFF4", "#9AA4B2",
                "#2B313C", "#171B22", "#314158", "#7CC2FF"
            )
        case .light, .system:
            return (
                "light", "#FBFBFC", "#1C1F26", "#5F6B7A",
                "#D8DEE8", "#F3F5F8", "#C5D4EA", "#0A66D1"
            )
        }
    }
}
