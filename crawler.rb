# frozen_string_literal: true

t1 = Time.now
puts "Started at: #{t1}"

system("relaton fetch-data ogc-naming-authority")

t2 = Time.now
puts "Stopped at: #{t2}"
puts "Done in: #{(t2 - t1).round} sec."
