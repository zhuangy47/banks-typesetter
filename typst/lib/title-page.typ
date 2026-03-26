// Title page layout for Banks of the Boneyard

#import "theme.typ": *

// Double rule: two thin lines tightly spaced
#let double-rule() = block(spacing: 0pt, {
  set block(spacing: 0pt)
  line(length: 100%, stroke: 1pt + rule-color)
  v(2pt)
  line(length: 100%, stroke: 1pt + rule-color)
})

// Centered section heading with short underline
#let section-title(body) = {
  align(center, {
    text(size: section-heading-size, weight: "bold", font: heading-font)[#body]
    v(2pt)
    line(length: 30%, stroke: 0.5pt + rule-color)
  })
}

#let title-page(data) = {
  let config = data.config
  let toc = data.toc
  let events = data.events
  let lftc = data.lftc
  let mode = data.mode

  // --- Banner: ACM logo | Banks logo image | Urbana, IL ---
  grid(
    columns: (auto, 1fr, auto),
    align: (left + horizon, center + horizon, right + horizon),
    image("/logo/acm-logo.png", height: 60pt),
    image("/logo/banks-logo.png", height: 80pt),
    text(size: body-size, weight: "bold")[Urbana, IL],
  )

  v(-12pt)

  // --- Subtitle ---
  align(center,
    text(size: subtitle-size)[
      #config.subtitle
    ]
  )

  v(8pt)

  // --- Volume/Issue | Date | URL ---
  block(spacing: 0pt, line(length: 100%, stroke: 0.5pt + rule-color))
  v(4pt)
  grid(
    columns: (1fr, 1fr, 1fr),
    align: (left, center, right),
    text(size: body-size)[
      Volume #str(config.volume), Issue #str(config.issue)
    ],
    text(size: body-size, style: "italic", weight: "bold")[
      #upper(config.date)
    ],
    {
      if mode == "online" {
        text(size: body-size)[
          #link(config.url)[#config.url]
        ]
      } else {
        text(size: body-size)[#config.url]
      }
    },
  )
  v(4pt)
  block(spacing: 0pt, line(length: 100%, stroke: 0.5pt + rule-color))

  // --- Large headline ---
  v(32pt)
  align(center,
    text(size: headline-size, weight: "bold", font: heading-font)[
      #config.headline
    ]
  )
  v(8pt)

  // --- Letter from the Chair ---
  align(center, {
    text(size: 18pt, weight: "bold", font: heading-font)[
      Letter from the Chair
    ]
    linebreak()
    v(1pt)
    text(size: body-size, weight: "bold")[
      By #lftc.author
    ]
  })
  v(4pt)
  align(center, block(spacing: 0pt, line(length: 40%, stroke: 0.5pt + rule-color)))
  v(8pt)

  block(width: 100%, {
    set text(size: body-size, font: body-font)
    set par(justify: true, first-line-indent: 0pt)
    include("/build/lftc.typ")
  })

  v(8pt)

  // --- Double rule separator ---
  double-rule()

  v(1fr)

  // --- Two columns: TOC | Events ---
  grid(
    columns: (1fr, 1fr),
    gutter: 16pt,
    // Left: In This Issue
    {
      section-title[In This Issue]
      v(8pt)
      for entry in toc {
        block(spacing: 6pt, {
          grid(
            columns: (1fr, auto),
            gutter: 4pt,
            {
              text(size: body-size)[#entry.title ]
              box(width: 1fr, repeat[.])
            },
            text(size: body-size)[ #str(entry.page + 1)],
          )
        })
      }
    },
    // Right: Upcoming Events
    {
      section-title[Upcoming Events]
      v(8pt)
      for event in events {
        block(spacing: 6pt, {
          text(size: body-size, weight: "bold")[#event.name]
          linebreak()
          text(size: body-size, style: "italic")[
            #event.date
            #if "time" in event { [ · #event.time] }
            #if "location" in event { [ · #event.location] }
          ]
          if "description" in event {
            linebreak()
            text(size: small-size)[#event.description]
          }
        })
      }
    },
  )

  v(1fr)

  // --- Footer ---
  grid(
    columns: (3fr, 2fr),
    gutter: 12pt,
    // Get Featured box
    block(
      width: 100%,
      inset: 8pt,
      stroke: 1pt + rule-color,
      {
        text(size: 13pt, weight: "bold")[Get Featured in Banks!]
        linebreak()
        text(size: body-size)[
          Want to submit an article to Banks? Send your article to
        ]
        linebreak()
        if mode == "online" {
          text(size: body-size)[#link("mailto:" + config.featured_email)[#config.featured_email]]
        } else {
          text(size: body-size)[#config.featured_email]
        }
      }
    ),
    // Editors box
    block(
      width: 100%,
      inset: 8pt,
      stroke: 1pt + rule-color,
      {
        text(size: 13pt, weight: "bold")[Editors]
        for editor in config.editors {
          linebreak()
          text(size: body-size)[#editor]
        }
      }
    ),
  )
}
