#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'pathname'
require 'tmpdir'

Script_path = Pathname.new($PROGRAM_NAME).expand_path
Script_name = Script_path.basename

# Check for minimum ruby version
abort "#{Script_name} requires Ruby 2.7 or higher" if RUBY_VERSION.to_f < 2.7

# Exit cleanup
Tmp_dir = Pathname.new(Dir.mktmpdir)
at_exit do Tmp_dir.rmtree end

# Helpers
def app_running?(bundle_id)
  Open3.capture3(
    '/usr/bin/osascript', '-l', 'JavaScript', '-e',
    "function run(argv) { return Application(argv[0]).running() }", bundle_id
  ).first.strip == 'true'
end

def app_installed?(app_token, definitions = All_apps)
  definition = definitions[app_token]
  bundle_ids = definition['ids']

  return true if bundle_ids&.any? { Open3.capture3('/usr/bin/defaults', 'read', _1).last.success? }
  return true if definition['paths']&.any? { Pathname.new(_1).expand_path.exist? }

  false
end

def copy_path(source, target)
  return unless Pathname.new(source).exist? # If path does not exist, do not try to copy it

  target.dirname.mkpath # Repeat directory structure of copied path
  FileUtils.rm_rf(target) # Delete target path before trying to copy
  FileUtils.cp_r(source, target)
end

def backup_app(app_token, definitions = All_apps)
  definition = definitions[app_token]
  backup_dir = Tmp_dir.join(definition['name'])
  bundle_ids = definition['ids']

  puts "Backing up #{definition['name']}…"

  # Backup preferences
  backup_dir.mkpath

  bundle_ids&.each do
    system('/usr/bin/defaults', 'export', _1, backup_dir.join("#{_1}.plist").to_path)
  end

  # Backup paths
  definition['paths']&.each do
    copy_path(Pathname.new(_1).expand_path, backup_dir.join(_1))
  end
end

def restore_app(app_token, definitions = All_apps)
  definition = definitions[app_token]
  backup_dir = Tmp_dir.join(definition['name'])
  bundle_ids = definition['ids']

  puts "Restoring backup for #{definition['name']}…"

  # Restore preferences
  bundle_ids&.each do
    system('/usr/bin/defaults', 'import', _1, backup_dir.join("#{_1}.plist").to_path)
  end

  # Restore paths
  definition['paths']&.each do
    copy_path(backup_dir.join(_1), Pathname.new(_1).expand_path)
  end

  # Warn if app is running
  return unless bundle_ids&.any? { app_running?(_1) }

  puts "#{definition['name']} is running. You may need to restart it for settings to take effect."
end

def update_definitions(force: false)
  local_hash_file = Config_dir.join('latest_hash.txt')

  # Skip if updated in the last hour, unless forced
  return if !force && local_hash_file.exist? && (Time.now - local_hash_file.mtime) < 3600

  puts 'Updating definitions…'

  # Check if there have been any updates
  local_hash = local_hash_file.exist? ? local_hash_file.read.chomp : nil

  remote_hash = JSON.parse(Open3.capture2(
    '/usr/bin/curl', '--silent', 'https://api.github.com/repos/vitorgalvao/tape/commits/main'
  ).first)['sha']

  local_hash_file.write(remote_hash)
  return if remote_hash == local_hash

  # Update
  system('/usr/bin/curl', '--silent', 'https://raw.githubusercontent.com/vitorgalvao/tape/main/definitions.json', '--output', Definitions_file.to_path)
end

# Usage
def usage
  puts <<~USAGE
    Backup and restore software settings on macOS

    Usage:
      #{Script_name} backup                Update definitions and backup settings
      #{Script_name} restore <tgz> [def]   Restore settings from previous backup
                                 Giving a definition name restores only that software
      #{Script_name} list                  Show names of supported software separated by what will be backed up
      #{Script_name} list tokens           Show tokens of supported software separated by what will be backed up
      #{Script_name} launchd <on|off>      Load or unload an agent to perform daily backups
      #{Script_name} update                Force update of backup definitions
      #{Script_name} version               Show #{Script_name} version
      #{Script_name} help                  Show this help
  USAGE

  exit
end

usage if ARGV.empty? || ARGV.include?('help') || ARGV.include?('--help') || ARGV.include?('-h')

# Load config
Config_dir = Pathname.new(ENV['HOME']).join('.config', 'tape')
Config_file = Config_dir.join('config.json')

Default_config = {
  backup_to: Config_dir.join('Backups').to_path, # Directory to save backups (leading "~" is expanded)
  keep: 5, # Number of backups to keep
  exclude: ['ssh'], # By default, backup everything except what is on this list
  include: [] # If set, *only* these will be backed up and the "exclude" list will be ignored
}.freeze

unless Config_file.exist?
  Default_config_json = JSON.pretty_generate(Default_config)
  warn "No config file found. One with default settings was saved to #{Config_file}:\n#{Default_config_json}\n"

  Config_dir.mkpath
  Config_file.write(Default_config_json)
end

Config = JSON.load_file(Config_file)

abort '"keep" value in configuration needs to be a whole number bigger than 0' unless Config['keep'].positive?

# Collect software to backup or restore
Backups_dir = Pathname.new(Config['backup_to']).expand_path
Definitions_file = Config_dir.join('definitions.json')

# Launchd for automatic backups
Launchd_file = Pathname.new(ENV['HOME']).join('Library', 'LaunchAgents', 'com.vitorgalvao.tape.plist')

Launchd_contents = <<~LAUNCHD_PLIST
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>Label</key>
      <string>com.vitorgalvao.tape</string>
      <key>EnvironmentVariables</key>
      <dict>
          <key>PATH</key>
          <string>/opt/homebrew/opt/ruby/bin:/usr/local/opt/ruby/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
      </dict>
      <key>ProgramArguments</key>
      <array>
          <string>#{Script_path}</string>
          <string>backup</string>
      </array>
      <key>StandardOutPath</key>
      <string>/tmp/tape_backup.log</string>
      <key>StandardErrorPath</key>
      <string>/tmp/tape_backup.log</string>
      <key>StartCalendarInterval</key>
      <dict>
          <key>Hour</key>
          <integer>20</integer>
          <key>Minute</key>
          <integer>0</integer>
      </dict>
  </dict>
  </plist>
LAUNCHD_PLIST

# Main
# Update definitions
update_definitions

All_apps = JSON.load_file(Definitions_file)

case ARGV[0]
when 'backup'
  # Backup selected and valid apps
  (Config['include'].empty? ? All_apps.keys - Config['exclude'] : Config['include'])
    .select { app_installed?(_1) }
    .each do backup_app(_1) end

  # Archive
  puts 'Archiving…'
  Backups_dir.mkpath

  system(
    '/usr/bin/tar', '--gzip', '--create',
    '--file', Backups_dir.join("#{Time.now.strftime('%Y-%m-%d')}.tgz").to_path,
    '--directory', Tmp_dir.to_path, '.'
  )

  # Remove older backups
  Backups_dir
    .children
    .select { _1.extname == '.tgz' }
    .sort
    .reverse
    .drop(Config['keep'])
    .each do _1.delete end
when 'restore'
  abort 'Restore needs a path to a valid .tgz' if ARGV[1].nil? || Pathname.new(ARGV[1]).extname != '.tgz'

  # Unarchive
  system(
    '/usr/bin/tar', '--extract',
    '--file', ARGV[1],
    '--directory', Tmp_dir.to_path
  )

  # Restore apps available in backup
  Apps_to_restore = ARGV[2] ? [ARGV[2]] : All_apps.keys

  Apps_to_restore.each do |app_token|
    begin
      name = All_apps[app_token]['name']
    rescue Errno::ENOENT
      abort "No defintion for #{app_token}"
    end

    next unless Tmp_dir.join(name).exist? # Skip if app directory does not exist in backup
    restore_app(app_token)
  end
when 'list'
  included = (Config['include'].empty? ? All_apps.keys - Config['exclude'] : Config['include']).select { app_installed?(_1) }
  excluded = All_apps.keys - included

  if ARGV[1] == 'tokens'
    puts excluded.map { "\e[31m✗\e[0m #{_1}" }.join("\n")
    puts included.map { "\e[32m✗\e[0m #{_1}" }.join("\n")
    exit
  end

  puts excluded.map { All_apps[_1]['name'] }.map { "\e[31m✗\e[0m #{_1}" }.join("\n")
  puts included.map { All_apps[_1]['name'] }.map { "\e[32m✓\e[0m #{_1}" }.join("\n")
when 'launchd'
  if ARGV[1] == 'on'
    Launchd_file.dirname.mkpath
    Launchd_file.write(Launchd_contents)

    system(
      'launchctl', 'bootstrap',
      "gui/#{Open3.capture2('/usr/bin/id', '-u', ENV['USER']).first}",
      Launchd_file.to_path
    )

    exit
  end

  if ARGV[1] == 'off'
    system(
      'launchctl', 'bootout',
      "gui/#{Open3.capture2('/usr/bin/id', '-u', ENV['USER']).first}",
      Launchd_file.to_path
    )

    Launchd_file.delete

    exit
  end

  # If we reach this point, wrong argument was given
  abort 'Launchd needs an argument of "on" or "off"'
when 'update'
  update_definitions(force: true)
when 'version'
  puts '2022.4'
else
  abort <<~INVALID
    Invalid argument. Try:

      #{Script_path} help
  INVALID
end
