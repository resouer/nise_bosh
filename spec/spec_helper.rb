def current_ip()
  %x[ip -4 -o address show].match('inet ([\d.]+)/.*? scope global') { |md| md[1] }
end

def setup_directory(path)
  FileUtils.rm_rf(path)
  FileUtils.mkdir_p(path)
end

def expect_contents(*path)
  expect(File.read(File.join(path)))
end

def expect_file_exists(*path)
  expect(File.exists?(File.join(path)))
end

def expect_directory_exists(*path)
  expect(File.directory?(File.join(path)))
end

def expect_to_same(path1, path2, both = nil)
  path1 = [path1] << both if both
  path2 = [path2] << both if both
  expect(File.read(File.join(path1))).to eq(File.read(File.join(path2)))
end

def expect_to_has_same_files(path1, path2, both =[])
  path1 = [path1] << both if both
  path2 = [path2] << both if both
  path1 = File.join(path1)
  path2 = File.join(path2)
  files1 = Dir::glob("#{path1}/**/*").map {|f| f[path1.length..-1]}
  files2 = Dir::glob("#{path2}/**/*").map {|f| f[path2.length..-1]}
  raise "No file found in the given directory" if files1.length == 0
  expect(files1.sort!).to eq(files2.sort!)
  files1.each_with_index do |f, i|
    f1 = File.join(path1, f)
    if File.file?(f1)
      expect(File.read(f1)).to eq(File.read(File.join(path2, f)))
    end
  end
end

def expect_file_mode(*path)
  expect(File.stat(File.join(File.join(*path))).mode)
end
