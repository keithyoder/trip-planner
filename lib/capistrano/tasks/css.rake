namespace :css do
  desc 'Build CSS'
  task :build do
    on roles(:web) do
      within release_path do
        with rails_env: fetch(:rails_env) do
          execute :rake, 'css:build'
        end
      end
    end
  end
end

# Hook it to run before assets:precompile
before 'deploy:assets:precompile', 'css:build'