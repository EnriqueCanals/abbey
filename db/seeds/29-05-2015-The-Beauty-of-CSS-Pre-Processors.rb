begin
  Post.create!(
    title: "The Beauty of CSS Pre Processors | An Introduction",
            created_at: "May 29, 2015",
            markdown_body: "\u003cscript async class=\"speakerdeck-embed\" data-id=\"4d3cd43e638b4fa19e7b274971221ddd\" data-ratio=\"1.33507170795306\" src=\"//speakerdeck.com/assets/embed.js\"\u003e\u003c/script\u003e",
            markdown_excerpt: "\u003cscript async class=\"speakerdeck-embed\" data-id=\"4d3cd43e638b4fa19e7b274971221ddd\" data-ratio=\"1.33507170795306\" src=\"//speakerdeck.com/assets/embed.js\"\u003e\u003c/script\u003e"
  )
  puts "Imported #{"The Beauty of CSS Pre Processors | An Introduction"}"
rescue ActiveRecord::RecordInvalid => e
  puts "Error importing 29-05-2015-The-Beauty-of-CSS-Pre-Processors.markdown: #{e.message}"
rescue => e
  puts "Unexpected error importing 29-05-2015-The-Beauty-of-CSS-Pre-Processors.markdown: #{e.message}"
end
