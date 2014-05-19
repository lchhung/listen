module Listen
  module Adapter
    # Adapter implementation for Windows `wdm`.
    #
    class Windows < Base
      # The message to show when wdm gem isn't available
      #
      BUNDLER_DECLARE_GEM = <<-EOS.gsub(/^ {6}/, '')
        Please add the following to your Gemfile to avoid polling for changes:
          require 'rbconfig'
          if RbConfig::CONFIG['target_os'] =~ /mswin|mingw|cygwin/i
            gem 'wdm', '>= 0.1.0'
          end
      EOS

      def self.usable?
        if RbConfig::CONFIG['target_os'] =~ /mswin|mingw|cygwin/i
          require 'wdm'
          true
        end
      rescue LoadError
        Kernel.warn BUNDLER_DECLARE_GEM
        false
      end

      def start
        worker = _init_worker
        Thread.new { worker.run! }
      end

      private

      # Initializes a WDM monitor and adds a watcher for
      # each directory passed to the adapter.
      #
      # @return [WDM::Monitor] initialized worker
      #
      def _init_worker
        WDM::Monitor.new.tap do |worker|
          _directories_path.each do |path|
            worker.watch_recursively(path.to_s, :files,
                                     &_worker_file_callback)

            worker.watch_recursively(path.to_s, :directories,
                                     &_worker_dir_callback)

            worker.watch_recursively(path.to_s, :attributes, :last_write,
                                     &_worker_attr_callback)
          end
        end
      end

      def _worker_file_callback
        lambda do |change|
          begin
            path = _path(change.path)
            options = { type: 'File', change: _change(change.type) }
            _notify_change(path, options)
          rescue
            _log :error, "wdm - callback failed: #{$!}:#{$@.join("\n")}"
            raise
          end
        end
      end

      def _worker_attr_callback
        lambda do |change|
          begin
            path = _path(change.path)
            return if path.directory?

            options = { type: 'File', change: _change(change.type) }
            _notify_change(_path(change.path), options)
          rescue
            _log :error, "wdm - callback failed: #{$!}:#{$@.join("\n")}"
            raise
          end
        end
      end

      def _worker_dir_callback
        lambda do |change|
          begin
            path = _path(change.path)
            if change.type == :removed
              _notify_change(path.dirname, type: 'Dir')
            elsif change.type == :added
              _notify_change(path, type: 'Dir')
            else
              # do nothing - changed directory means either:
              #   - removed subdirs (handled above)
              #   - added subdirs (handled above)
              #   - removed files (handled by _worker_file_callback)
              #   - added files (handled by _worker_file_callback)
            end
          rescue
            _log :error, "wdm - callback failed: #{$!}:#{$@.join("\n")}"
            raise
          end
        end
      end

      def _path(path)
        Pathname.new(path)
      end

      def _change(type)
        { modified: [:modified],
          added:    [:added, :renamed_new_file],
          removed:  [:removed, :renamed_old_file] }.each do |change, types|
          return change if types.include?(type)
        end
        nil
      end

      def _log(type, message)
        Celluloid.logger.send(type, message)
      end
    end
  end
end
