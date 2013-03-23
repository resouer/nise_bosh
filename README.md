[![Build Status](https://travis-ci.org/nttlabs/nise_bosh.png?branch=master)](https://travis-ci.org/nttlabs/nise_bosh)

# Nise BOSH

## What's this

Nise BOSH is a lightweight BOSH emulator. You can easily install multiple BOSH packages on your servers by Nise BOSH commands. 'Nise' means 'Pseudo' in Japanese.

## Requirements

* Ubuntu 10.04, 12.04
 * Ubuntu 10.04 64bit is recmmended when you install cf-release jobs.
* Ruby 1.9.2 or higher
* Bundler

## How to use

### Install required gems

You can install the requried gems to execute Nise BOSH commands with bundler.

Run the command below:

    bundle install

### Release repository

Nise BOSH requries a clone of the 'release' repository you want to install (e.g. cf-release for Cloud Foundry). Clone the repository and checkout its submodules at your preferred directory.

    git clone git@github.com:cloudfoundry/cf-release.git
    cd cf-release
    git submodule sync
    git submodule update --init --recursive

### Build a release

You have to build a release of your release repository to create package tarballs.

If you have not installed BOSH CLI. You can install it with `gem` command.

    gem install bosh_cli

Then build a release, this might takes several minutes at the first run.

    bosh create release

You shall be asked the name of the build, input a preferred name such as 'appcloud'.

The command generates "dev_releases" and ".dev_builds" directories in your cloned release directory. You can find the "release file" for the build at "dev_release/\<build_name\>-\<viersion\>-dev.yml", which includes the list of all the packages and jobs, and their dependencies.

Note that, when you have any modification in your release repository, you have to commit them once before buliding a new release. You might need to execute 'bosh create release ' with "--force" option, when you have added new files into the blobs directory.

### Describe a deployment manifest

Nise-BOSH requires a deployment manifest which contains the configuration of your release. Nise-BOSH's manifest file is compatible with, or subset of Bosh's manifest format.

You can find an example at [Cloud foundry's OSS docs](https://github.com/cloudfoundry/oss-docs/blob/master/bosh/tutorial/examples/bosh_manifest.yml).

    ---
    properties:
      domain: vcap.me
    
      networks:
        apps: default
        management: default
    
      nats:
        user: nats
        password: nats
        address: 127.0.0.1
        port: 4222
    
      dea_next:
        streaming_timeout: 60
        memory_mb: 4096
        memory_overcommit_factor: 1
        disk_mb: 32000
        disk_overcommit_factor: 1
        num_instances: 30

### Run

Run `nise-bosh` command. You may want to run with 'sudo' and/or 'bundle exec'

    ./bin/nise-bosh <path_to_release_repository> <path_to_deploy_manifest> <job_name>

Example:

    sudo PATH=$PATH bundle exec ./bin/nise-bosh ~/cf-release ~/deploy.conf dea_next

### Initialize the environment (optional)

You need to install and create required apt packages and users on your environemnt to execute certain job processes from cf-release. The original BOSH sets up the environment using a stemcell, but Nise-BOSH does not support it. You can simulate a stemcell-like environment on your server by executing the `bin/init` script.

    sudo ./bin/init

This script runs the minimal (sometimes insufficient) commands extracted from the stemcell-builder stages.

### Create stemcell_base.tar.gz (optional)

Some packages require `/var/vcap/stemcell_base.tar.gz` file to create Warden containers. You can create the file by executing the `bin/gen-stemcell` script.

    sudo ./bin/gen-stemcell

### Launch processes

Once instllation is complete, you can launch job processes by `run-job` command.

    ./bin/run-job start

This command automatically loads the monitrc file (default in: /var/vcap/bosh/etc/monitrc) and start all the processes defined in it. You can also invoke stop and status commands by giving an option.

    ./bin/run-job status
    ./bin/run-job stop

## Command line options

### '-y': Assume yes as an answer to all prompts

Nise-BOSH do not ask any prompts.

### '-f': Force install packages

By default, Nise-BOSH do not re-install packages which are already installed. This option forces Nise BOSH to re-install all packages.

### '-d': Install directory

Nise-BOSH installs packages into this directory. The default value is `/var/vcap`. Be careful to change this value because some packages given by cf-release have hard-coded directory names in their packaging scripts and template files.

### '--working-dir': Temporary working directory

Nise-BOSH uses the given directory to run packaging scripts. The default value is `/tmp/nise_bosh`.

### '-t': Install template files only

Nise-BOSH do not install the required packages for the given job. Nise-BOSH only fills template files for the given job and write out them to the install directory.

### '-r': Release file

Nise-BOSH uses the given release file for deploy not the newest release file. By default, Nise BOSH automatically detect the newest release file.

### '-n': IP address for the host

Nise-BOSH assumes the IP address of your host using 'ifconfig eth0' command. You can overwrite the IP address of your host by this option.

### '-i': Index number for the host

Nise-BOSH assumes the index number of your host as 0 by default. When you install the same job on multiple hosts, you can set the index number by this option. The value "spec.index" in job template files is replaced by this value.

### '-p': Install specific packages

Nise-BOSH install the given packages, not a job. When this option choosen, file path for the deploy manifest file must be ommited.

Example:

    sudo PATH=$PATH bundle exec ./bin/nise-bosh -p ~/cf-release_interim dea_jvm dea_ruby

### '--no-dependency': Install no dependeny packages

Nise-BOSH does not install dependency packages. This option must be used with '-c' option.

### '-a': Create an archive file for a job

Nise-BOSH aggregates the packages and the index file required to install the given job and create an archive file includes them. This behavior is similar to 'bosh create release --with-tarball', but the generated archive file contains the minimum packages to install the given job.

## Appendix

### stemcell_base.tar.gz builder

You can generate stemcell_base.tar.gz for the rootfs of Warden containers by 'gen-stemcell' command. Default config files are found in the config directory. Before executing, change the password for containers in config/stemcell-settings.sh.

    sudo ./bin/gen-stemcell [<output_filename_or_directory>]

The generated archive file are placed on /var/vcap/stemcell_base.tar.gz by default. You can change the path and other behaviour by giving command line options shown by the '--help' option.

### init

You can install basic apt packages and create user for the BOSH stemcell with this command.

### bget

You can download objects from the blobstore for cf-release by using 'bget' command.

    ./bin/bget -o <output_file_name> <object_id>

## License

Apache License Version 2.0

The original BOSH is developed by VMware, inc. and distributed under Apache License Version 2.0.
