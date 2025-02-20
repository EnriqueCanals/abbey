begin
  Post.create!(
    title: "Issues Installing Capybara-Webkit on OS X 10.9 (Mavericks)",
            created_at: "November 5, 2013",
            markdown_body: "#__November 05, 2013__\n\n**_Fix issues with Qt and qmake on OS X 10.9 Mavericks_**\n\n\nI just recently decided to upgrade to OS X 10.9 from 10.8 and ran into a pretty crappy issue while installing the capybara-webkit gem. When running bundle install, I received the following error\n\n{% highlight bash %}\n  Building native extensions.  This could take a while...\n  ERROR:  Error installing capybara-webkit:\n  ERROR: Failed to build gem native extension.\n\n  /Users/$USER/.rvm/rubies/ruby-2.0.0-p247/bin/ruby extconf.rb\n  Command 'qmake -spec macx-g++' not available\n{% endhighlight %}\n\nAfter some searching I was able to find several posts mentioning that the most recent stable version of Qt isn't fully supported on 10.9. As such, I decided to try the beta which worked!\n\n**Step 1:**\nDownload Qt 5.2.0-beta-1-clang [HERE](http://download.qt-project.org/development_releases/qt/5.2/5.2.0-beta1/).\n\n**Step 2:**\nInstall it and include the Src files.\n\n**Step 3:**\nSymlink qmake into your /bin directory from the location where you installed Qt. The default location is in your home directory. Open a shell and do something like:\n\n{% highlight bash %}\n  ln -s /Path/to/where/you/installed/Qt5.2/5.2.0-beta1/clang_64/bin/qmake /usr/local/bin/qmake\n{% endhighlight %}\n\nThat should do it. Now when you gem install capybara-webkit it shouldn't bitch about qmake not being available.\n\nNow go compute!",
            markdown_excerpt: "#__November 05, 2013__ **_Fix issues with Qt and qmake on OS X 10.9 Mavericks_** I just recently decided to upgrade to OS X 10.9 from"
  )
  puts "Imported #{"Issues Installing Capybara-Webkit on OS X 10.9 (Mavericks)"}"
rescue ActiveRecord::RecordInvalid => e
  puts "Error importing 11-05-2013-Error-with-capybara-webkit-on-os-x-Mavericks.markdown: #{e.message}"
rescue => e
  puts "Unexpected error importing 11-05-2013-Error-with-capybara-webkit-on-os-x-Mavericks.markdown: #{e.message}"
end
