describe "RunJobCommand" do
  let(:pid_dir) { File.join(%w{/ tmp nise_bosh_spec run}) }
  let(:processes) { %w{nendoroid angel android} }
  let(:pid_files) { processes.map { |process| pid_file = File.join(pid_dir, "#{process}.pid") } }

  before do
    FileUtils.rm_rf(pid_dir)
  end

  it "should raise an error when the command not given" do
    out = %x[./bin/run-job -m ./spec/assets/monitrc 2>&1]
    expect($?.exitstatus).to eq(1)
    expect(out.match(/^Invalid command given.$/)).to be_true
  end

  it "should raise an error when an invalid command given" do
    out = %x[./bin/run-job -m ./spec/assets/monitrc nop 2>&1]
    expect($?.exitstatus).to eq(1)
    expect(out.match(/^Invalid command given.$/)).to be_true
  end

  it "should raise an error when an invalid monitrc given" do
    out = %x[./bin/run-job -m ./not/exist/monitrc start 2>&1]
    expect($?.exitstatus).to eq(1)
    expect(out.match(/^Monitrc file not found at .\/not\/exist\/monitrc$/)).to be_true
  end

  it "should start/stop processes" do
    out = %x[./bin/run-job -m ./spec/assets/monitrc start 2>&1]
    expect($?.exitstatus).to eq(0)
    expect(out).to eq("android: \e[32mRUNNING\e[0m\nangel: \e[32mRUNNING\e[0m\nnendoroid: \e[32mRUNNING\e[0m\n")
    pids = []
    pid_files.each do |pid_file|
      expect_file_exists(pid_file).to be_true
      pid = File.read(pid_file).strip
      expect(File.directory?("/proc/#{pid}")).to be_true
      pids << pid
    end

    out = %x[./bin/run-job -m ./spec/assets/monitrc stop 2>&1]
    expect(out).to eq("android: \e[31mSTOPPED\e[0m\nnendoroid: \e[31mSTOPPED\e[0m\nangel: \e[31mSTOPPED\e[0m\n")
    expect($?.exitstatus).to eq(0)
    pid_files.each do |pid_file|
      expect_file_exists(pid_file).to be_false
    end
    pids.each do |pid|
      expect(File.directory?("/proc/#{pid}")).to be_false
    end
  end

  it "should get the status of the running processes" do
    out = %x[./bin/run-job -m ./spec/assets/monitrc status 2>&1]
    expect($?.exitstatus).to eq(0)
    expect(out).to eq("android: \e[31mSTOPPED\e[0m\nnendoroid: \e[31mSTOPPED\e[0m\nangel: \e[31mSTOPPED\e[0m\n")

    out = %x[./bin/run-job -m ./spec/assets/monitrc start 2>&1]
    out = %x[./bin/run-job -m ./spec/assets/monitrc status 2>&1]
    expect($?.exitstatus).to eq(0)
    expect(out).to eq("android: \e[32mRUNNING\e[0m\nnendoroid: \e[32mRUNNING\e[0m\nangel: \e[32mRUNNING\e[0m\n")
    out = %x[./bin/run-job -m ./spec/assets/monitrc stop]
  end

  it "should cancel launching depending processes when depended process has failed starting" do
    out = %x[./bin/run-job -m ./spec/assets/monitrc_fail start]
    expect($?.exitstatus).to eq(1)
    expect(out).to eq("angel: \e[31mFAILD\e[0m\nnendoroid: \e[31mFAILD\e[0m\n")
  end

end
