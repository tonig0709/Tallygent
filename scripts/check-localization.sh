#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Pure resource validation. Never launches an account connection or changes language preferences.
ruby -rjson -ropen3 - "$@" <<'RUBY'
locales = %w[en zh-Hans zh-Hant]
def table(path)
  out, err, status = Open3.capture3('plutil', '-convert', 'json', '-o', '-', path)
  abort "Invalid localization table #{path}: #{err}" unless status.success?
  JSON.parse(out)
end
def formats(value)
  value.scan(/%(?:\d+\$)?[-+0# ']*\d*(?:\.\d+)?(?:hh|ll|[hlztjL])?[diuoxXfFeEgGaAcCsSp@%]/).reject { |v| v == '%%' }.sort
end
tables = locales.to_h { |locale| [locale, table("Resources/#{locale}.lproj/Localizable.strings")] }
source = tables.fetch('zh-Hans')
abort 'Localization catalog is unexpectedly empty' unless source.length > 250
tables.each do |locale, values|
  abort "Missing/extra keys in #{locale}" unless values.keys.sort == source.keys.sort
  values.each do |key, value|
    abort "Empty translation: #{locale}: #{key}" unless value.is_a?(String) && !value.strip.empty?
    abort "Untranslated Chinese in English: #{key}" if locale == 'en' && value.match?(/\p{Han}/)
  end
end
sources = Dir['App/*.swift', 'Shared/*.swift'].to_h { |path| [path, File.read(path)] }
sources.each do |path, text|
  text.scan(/\b(LF?)\("((?:\\.|[^"\\])*)"/).each do |function, raw|
    key = JSON.parse('"' + raw + '"') rescue abort("Dynamic localization key: #{path}: #{raw}")
    abort "Uncatalogued key: #{path}: #{key}" unless source.key?(key)
    if function == 'LF'
      tables.each do |locale, values|
        abort "Unsafe format translation: #{locale}: #{key}" unless formats(key) == formats(values.fetch(key))
      end
    end
  end
  text.lines.each do |line|
    next if line.lstrip.start_with?('//')
    # These are input-classifier match terms, not presentation; translating them changes behavior.
    next if path == 'Shared/Planner.swift' && (line.include?('contains([') || line.include?('].contains(where: lower.contains)'))
    line.scan(/"((?:\\.|[^"\\])*)"/).flatten.select { |raw| raw.match?(/\p{Han}/) }.each do |raw|
      key = JSON.parse('"' + raw + '"') rescue abort("Uncatalogued Swift interpolation: #{path}: #{raw}")
      abort "Uncatalogued visible source text: #{path}: #{key}" unless source.key?(key)
    end
  end
end
project = File.read('CodexQuotaWidget.xcodeproj/project.pbxproj')
abort 'English fallback is not configured' unless project.include?('developmentRegion = en;')
locales.each { |locale| abort "Unregistered language #{locale}" unless project.include?("#{locale}.lproj/Localizable.strings") }
if app = ARGV[0]
  locales.each do |locale|
    packaged = table(File.join(app, 'Contents/Resources', "#{locale}.lproj/Localizable.strings"))
    abort "Packaged #{locale} differs from checked source" unless packaged == tables.fetch(locale)
  end
end
# A format-mismatch negative control must be rejected by the same comparison.
abort 'Format checker accepted a broken translation' if formats('%lld %@') == formats('%@ %@')
puts "Localization gate passed: #{source.length} keys, three complete tables, safe formats, native fallback#{ARGV[0] ? ', exact packaged resources' : ''}."
RUBY
probe_dir=$(mktemp -d)
trap 'rm -rf "$probe_dir"' EXIT
probe_app="$probe_dir/LocalizationProbe.app"
mkdir -p "$probe_app/Contents/MacOS" "$probe_app/Contents/Resources"
cp Gate/LocalizationProbeInfo.plist "$probe_app/Contents/Info.plist"
for language in en zh-Hans zh-Hant; do
    /usr/bin/ditto "Resources/$language.lproj" "$probe_app/Contents/Resources/$language.lproj"
done
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macos14.0" \
    -module-cache-path "$probe_dir/module-cache" Gate/LocalizationProbe.swift Shared/Localization.swift \
    -o "$probe_app/Contents/MacOS/localization-probe"
for language in en zh-Hans zh-Hant zh-CN zh-TW zh-HK fr; do
    expected="$language"
    case "$language" in zh-CN) expected=zh-Hans ;; zh-TW|zh-HK) expected=zh-Hant ;; fr) expected=en ;; esac
    TALLYGENT_EXPECT_LANGUAGE="$expected" "$probe_app/Contents/MacOS/localization-probe" \
        -AppleLanguages "(\"$language\")"
done
