// Banks of the Boneyard - Main Typst Entry Point

#import "lib/theme.typ": *
#import "lib/title-page.typ": title-page
#import "lib/article-page.typ": render-article-page, max-page
#import "lib/directory.typ": directory-page
#import "lib/horoscope.typ": horoscope-page

// Read mode from CLI input
#let mode = sys.inputs.at("mode", default: "online")
#let debug = sys.inputs.at("debug", default: "false") == "true"

// Load all data from build/data.json
#let data = json("/build/data.json")

// Page setup
#set page(
  paper: "us-letter",
  margin: (x: margin-x, y: margin-y),
)

#set text(
  font: body-font,
  size: body-size,
)

#set par(
  justify: true,
  leading: 0.5em,
)

// Link styling for online mode
#show link: it => {
  if mode == "online" {
    underline(text(fill: link-color, it))
  } else {
    it
  }
}

// === Title Page (must fit exactly one page) ===
#block(height: 100%, title-page(data))

// === Article Pages ===
#let num-pages = max-page(data.layout)

#for page-num in range(1, num-pages + 1) {
  pagebreak()
  render-article-page(page-num, data.layout, data.articles, mode, debug: debug)
}

// === Directory ===
#pagebreak()
#directory-page(data)

// === Horoscope (optional) ===
#if data.horoscope != none {
  pagebreak()
  horoscope-page(data)
}
