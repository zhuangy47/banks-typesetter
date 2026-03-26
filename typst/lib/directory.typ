// Directory section - two-column layout of all organizations

#import "theme.typ": *

#let format-day(day) = {
  let days = (
    "monday": "Mondays",
    "tuesday": "Tuesdays",
    "wednesday": "Wednesdays",
    "thursday": "Thursdays",
    "friday": "Fridays",
    "saturday": "Saturdays",
    "sunday": "Sundays",
  )
  days.at(day, default: day)
}

#let format-time(t) = {
  // t can be minutes since midnight (int) or "HH:MM" string
  let total-min = 0
  if type(t) == int {
    total-min = t
  } else {
    let parts = str(t).split(":")
    if parts.len() < 2 { return str(t) }
    total-min = int(parts.at(0)) * 60 + int(parts.at(1))
  }
  let hour = int(total-min / 60)
  let min = calc.rem(total-min, 60)
  let ampm = if hour >= 12 { "PM" } else { "AM" }
  let h12 = if hour > 12 { hour - 12 } else if hour == 0 { 12 } else { hour }
  let min-str = if min < 10 { "0" + str(min) } else { str(min) }
  str(h12) + ":" + min-str + " " + ampm
}

#let link-type-label(link-type) = {
  let labels = (
    "DISCORD": "Discord",
    "INSTAGRAM": "Instagram",
    "MATRIX": "Matrix",
    "GITHUB": "GitHub",
    "TWITTER": "Twitter",
    "LINKEDIN": "LinkedIn",
  )
  labels.at(link-type, default: link-type)
}

#let directory-page(data) = {
  let directory = data.directory
  let mode = data.mode

  align(center,
    text(size: section-heading-size, weight: "bold", font: heading-font)[
      ACM\@UIUC Directory
    ]
  )
  v(8pt)
  line(length: 100%, stroke: 1pt + rule-color)
  v(6pt)

  columns(2, gutter: 12pt, {
    for org in directory {
      block(spacing: 6pt, width: 100%, breakable: false, {
        // Org name + logo
        grid(
          columns: (28pt, 1fr),
          gutter: 6pt,
          align: (center + horizon, left + horizon),
          {
            if org.logo != "" {
              image(org.logo, height: 24pt, fit: "contain")
            }
          },
          text(size: 14pt, weight: "bold", font: heading-font)[#org.name],
        )

        // For ACM general: list leadership roles separately
        if org.at("type", default: "") == "main" and org.leads.len() > 0 {
          let role-order = ("Chair", "Vice Chair", "Treasurer", "Secretary")
          for role in role-order {
            let matches = org.leads.filter(l => l.title == role)
            if matches.len() > 0 {
              text(size: body-size, weight: "bold")[#role: ]
              text(size: body-size)[#matches.map(l => l.name).join(", ")]
              linebreak()
            }
          }
          // Any leads with titles not in role-order
          let other-leads = org.leads.filter(l => l.title not in role-order)
          if other-leads.len() > 0 {
            for l in other-leads {
              if l.title != "" {
                text(size: body-size, weight: "bold")[#l.title: ]
              }
              text(size: body-size)[#l.name]
              linebreak()
            }
          }
        } else if org.leads.len() > 0 {
          // Regular orgs: Chairs: name1, name2
          let lead-names = org.leads.map(l => l.name)
          text(size: body-size, weight: "bold")[Chairs: ]
          text(size: body-size)[#lead-names.join(", ")]
          linebreak()
        }

        // Website
        if org.website != "" and org.website != none {
          text(size: body-size, weight: "bold")[Website: ]
          text(size: body-size)[
            #if mode == "online" {
              link(org.website)[#org.website]
            } else {
              org.website
            }
          ]
          linebreak()
        }

        // Email
        if org.email != "" {
          text(size: body-size, weight: "bold")[Email: ]
          text(size: body-size)[
            #if mode == "online" {
              link("mailto:" + org.email)[#org.email]
            } else {
              org.email
            }
          ]
          linebreak()
        }

        // Meeting times
        if "meeting_times" in org and org.meeting_times != none and org.meeting_times.len() > 0 {
          text(size: body-size, weight: "bold")[Meetings: ]
          let mt-list = org.meeting_times
          for (i, mt) in mt-list.enumerate() {
            text(size: body-size)[
              #format-day(mt.date), #format-time(mt.start_time)–#format-time(mt.end_time), #mt.location
            ]
            if i < mt-list.len() - 1 {
              linebreak()
              // Indent continuation lines to align with first meeting
              h(1em)
              text(size: body-size)[#h(4.2em)]
            }
          }
          linebreak()
        }

        // Links (each on its own line with bold label)
        if org.links.len() > 0 {
          for l in org.links {
            text(size: body-size, weight: "bold")[#link-type-label(l.type): ]
            text(size: body-size)[
              #if mode == "online" {
                link(l.url)[#l.url]
              } else {
                l.url
              }
            ]
            linebreak()
          }
        }

        // Blurb
        if org.at("blurb", default: "") != "" {
          v(4pt)
          set par(justify: true, first-line-indent: 0pt)
          text(size: body-size)[#org.blurb]
        }

        v(4pt)
        line(length: 100%, stroke: 0.25pt + luma(180))
      })
    }
  })
}
