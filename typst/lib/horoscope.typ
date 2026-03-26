// Optional horoscope section

#import "theme.typ": *

#let horoscope-page(data) = {
  if data.horoscope == none { return }

  let horoscope = data.horoscope

  align(center,
    text(size: section-heading-size, weight: "bold", font: heading-font)[
      Horoscope
    ]
  )
  v(8pt)
  line(length: 100%, stroke: 1pt + rule-color)
  v(6pt)

  if "title" in horoscope {
    align(center,
      text(size: body-size, style: "italic")[#horoscope.title]
    )
    v(6pt)
  }

  columns(2, gutter: 12pt, {
    let signs = horoscope.at("signs", default: ())
    for sign in signs {
      block(spacing: 6pt, width: 100%, {
        text(size: 10pt, weight: "bold")[#sign.name]
        if "dates" in sign {
          text(size: tiny-size)[ (#sign.dates)]
        }
        linebreak()
        text(size: small-size)[#sign.text]
        v(3pt)
        line(length: 100%, stroke: 0.25pt + luma(180))
      })
    }
  })
}
