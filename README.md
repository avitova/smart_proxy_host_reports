# Smart Proxy Host Reports

Transforms configuration and security management reports into Foreman-friendly
JSON and sends them to a Foreman instance. For more information about Foreman
JSON report format, visit
[foreman_host_reports](https://github.com/theforeman/foreman_host_reports).

## Usage

Send a POST HTTP call to `/host_reports/FORMAT` where FORMAT is one of the following formats.

### Puppet

Accepts Puppet Server YAML format:

* [Example input](test/fixtures/puppet6-foreman-web.yaml)
* [Example output](test/snapshots/foreman-web.json)

## Development setup

Few words about setting up a dev setup.

### Ansible

Checkoud foreman-ansible-modules and build it via `make` command. Configure
Ansible collection path to the build directory:

    [defaults]
    collection_path = /home/lzap/work/foreman-ansible-modules/build
    callback_whitelist = foreman
    [callback_foreman]
    url = http://localhost:8448/host_reports
    verify_certs = 0
    client_cert = /home/lzap/DummyX509/client-one.crt
    client_key = /home/lzap/DummyX509/client-one.key

Configure Foreman Ansible callback with the correct Foreman URL:

Then call Ansible:

    ANSIBLE_LOAD_CALLBACK_PLUGINS=1 ansible localhost -m ping -vvv

## Example data

For testing, there are several example data. Before importing them into Foreman, make sure to have `localhost` smart proxy and also a host named `report.example.com`. It is possible to capture example data via `incoming_save_dir` setting. Name generated files correctly and put them into the `contrib/fixtures` directory. There is a utility to use fixtures for development and testing purposes:

```
$ contrib/upload-fixture
Usage:
  contrib/upload-fixture -h               Display this help message
  contrib/upload-fixture -u URL           Proxy URL (http://localhost:8448)
  contrib/upload-fixture -f FILE          Fixture to upload
  contrib/upload-fixture -a               Upload all fixtures

$ contrib/upload-fixture -a
contrib/fixtures/ansible-copy-nochange.json: 200
contrib/fixtures/ansible-copy-success.json: 200
contrib/fixtures/ansible-package-install-failure.json: 200
contrib/fixtures/ansible-package-install-nochange.json: 200
contrib/fixtures/ansible-package-install-success.json: 200
contrib/fixtures/ansible-package-remove-failure.json: 200
contrib/fixtures/ansible-package-remove-success.json: 200
```

### Importing into Foreman directly

To import a report directly info Foreman:

```
curl -H "Accept:application/json,version=2" -H "Content-Type:application/json" -X POST -d @test/snapshots/foreman-web.json http://localhost:5000/api/v2/host_reports
```

### Puppet

To install and configure a Puppetserver on EL7, run the following:

```bash
# Install the server - modify as needed for your platform
yum -y install https://yum.puppet.com/puppet7-release-el-7.noarch.rpm
yum -y install puppetserver
# Correct $PATH in the current shell - happens on start of fresh shells automatically
source /etc/profile.d/puppet-agent.sh
# Configure the HTTP report processor
puppet config set reports store,http
puppet config set reporturl http://$HOSTNAME:8000/host_reports/puppet
# Enable & start the service
systemctl enable --now puppetserver
```

By default an agent connects to `puppet` which may not resolve. Set it to your hostname:

```bash
puppet config set server $HOSTNAME
```

You can manually trigger a puppet run by using `puppet agent -t`. You may need to look at `/var/log/puppetlabs/puppetserver/puppetserver.log` to see errors.

## Contributing

Fork and send a Pull Request. Thanks!

## License

GNU GPLv3, see LICENSE file for more information.

## Copyright

Copyright (c) 2021 Red Hat, Inc.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
