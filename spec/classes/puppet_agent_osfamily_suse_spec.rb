require 'spec_helper'

describe 'puppet_agent' do
  package_version = '1.10.100'
  before(:each) do
    # Need to mock the PE functions
    Puppet::Parser::Functions.newfunction(:pe_build_version, :type => :rvalue) do |args|
      "2000.0.0"
    end

    Puppet::Parser::Functions.newfunction(:pe_compiling_server_aio_build, :type => :rvalue) do |args|
      package_version
    end
  end

  facts = {
    :is_pe                     => true,
    :osfamily                  => 'Suse',
    :operatingsystem           => 'SLES',
    :operatingsystemmajrelease => '12',
    :architecture              => 'x64',
    :servername                => 'master.example.vm',
    :clientcert                => 'foo.example.vm',
  }

  let(:params) do
    {
      :package_version => package_version
    }
  end

  describe 'unsupported environment' do
    context 'when not PE' do
      let(:facts) do
        facts.merge({
          :is_pe => false,
        })
      end

      it { expect { catalogue }.to raise_error(/SLES not supported/) }
    end

    context 'when not SLES' do
      let(:facts) do
        facts.merge({
          :is_pe           => false,
          :operatingsystem => 'OpenSuse',
        })
      end

      it { expect { catalogue }.to raise_error(/OpenSuse not supported/) }
    end
  end

  describe 'supported environment' do
    context "when operatingsystemmajrelease 10 is supported" do
      let(:facts) do
        facts.merge({
          :operatingsystemmajrelease => '10',
          :platform_tag              => "sles-10-x86_64",
          :architecture              => "x86_64",
        })
      end

      it { is_expected.to contain_file('/opt/puppetlabs') }
      it { is_expected.to contain_file('/opt/puppetlabs/packages') }
      it do
        is_expected.to contain_file('/opt/puppetlabs/packages/puppet-agent-1.10.100-1.sles10.x86_64.rpm').with_ensure('present')
        is_expected.to contain_file('/opt/puppetlabs/packages/puppet-agent-1.10.100-1.sles10.x86_64.rpm').with_source('puppet:///pe_packages/2000.0.0/sles-10-x86_64/puppet-agent-1.10.100-1.sles10.x86_64.rpm')
      end

      it { is_expected.to contain_class("puppet_agent::osfamily::suse") }
      it { is_expected.to contain_package('puppet-agent').with_ensure('1.10.100') }

      it do
        is_expected.to contain_package('puppet-agent').with_provider('rpm')
        is_expected.to contain_package('puppet-agent').with_source('/opt/puppetlabs/packages/puppet-agent-1.10.100-1.sles10.x86_64.rpm')
      end
    end

    context "when operatingsystemmajrelease 11 or 12 is supported" do
      ['11', '12'].each do |os_version|
        context "when SLES #{os_version}" do
          let(:facts) do
            facts.merge({
              :operatingsystemmajrelease => os_version,
              :platform_tag              => "sles-#{os_version}-x86_64",
            })
          end

          it { is_expected.to contain_exec('import-GPG-KEY-puppet').with({
            'path'      => '/bin:/usr/bin:/sbin:/usr/sbin',
            'command'   => 'rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-puppet',
            'unless'    => 'rpm -q gpg-pubkey-$(echo $(gpg --homedir /root/.gnupg --throw-keyids < /etc/pki/rpm-gpg/RPM-GPG-KEY-puppet) | cut --characters=11-18 | tr [:upper:] [:lower:])',
            'require'   => 'File[/etc/pki/rpm-gpg/RPM-GPG-KEY-puppet]',
            'logoutput' => 'on_failure',
          }) }

          it { is_expected.to contain_exec('import-GPG-KEY-puppetlabs').with({
            'path'      => '/bin:/usr/bin:/sbin:/usr/sbin',
            'command'   => 'rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-puppetlabs',
            'unless'    => 'rpm -q gpg-pubkey-$(echo $(gpg --homedir /root/.gnupg --throw-keyids < /etc/pki/rpm-gpg/RPM-GPG-KEY-puppetlabs) | cut --characters=11-18 | tr [:upper:] [:lower:])',
            'require'   => 'File[/etc/pki/rpm-gpg/RPM-GPG-KEY-puppetlabs]',
            'logoutput' => 'on_failure',
          }) }

          context 'with manage_pki_dir => true' do
            ['/etc/pki', '/etc/pki/rpm-gpg'].each do |path|
              it { is_expected.to contain_file(path).with({
                'ensure' => 'directory',
              }) }
            end
          end

          context 'with manage_pki_dir => false' do
            let(:params) {{ :manage_pki_dir => 'false' }}
            ['/etc/pki', '/etc/pki/rpm-gpg'].each do |path|
              it { is_expected.not_to contain_file(path) }
            end
          end

          it { is_expected.to contain_class("puppet_agent::osfamily::suse") }

          it { is_expected.to contain_file('/etc/pki/rpm-gpg/RPM-GPG-KEY-puppetlabs').with({
            'ensure' => 'present',
            'owner'  => '0',
            'group'  => '0',
            'mode'   => '0644',
            'source' => 'puppet:///modules/puppet_agent/GPG-KEY-puppetlabs',
          }) }

          it { is_expected.to contain_file('/etc/pki/rpm-gpg/RPM-GPG-KEY-puppet').with({
            'ensure' => 'present',
            'owner'  => '0',
            'group'  => '0',
            'mode'   => '0644',
            'source' => 'puppet:///modules/puppet_agent/GPG-KEY-puppet',
          }) }

          context "with manage_repo enabled" do
            let(:params) {
              {
                :manage_repo => true,
                :package_version => package_version
              }
            }

            {
              'name'        => 'pc_repo',
              'enabled'     => '1',
              'autorefresh' => '0',
              'baseurl'     => "https://master.example.vm:8140/packages/2000.0.0/sles-#{os_version}-x86_64?ssl_verify=no",
              'type'        => 'rpm-md',
            }.each do |setting, value|
              it { is_expected.to contain_ini_setting("zypper pc_repo #{setting}").with({
                'path'    => '/etc/zypp/repos.d/pc_repo.repo',
                'section' => 'pc_repo',
                'setting' => setting,
                'value'   => value,
              }) }
            end
          end

          context "with manage_repo disabled" do
            let(:params) {
              {
                :manage_repo => false,
                :package_version => package_version
              }
            }

            [
              'name',
              'enabled',
              'autorefresh',
              'baseurl',
              'type',
            ].each do |setting|
              it { is_expected.not_to contain_ini_setting("zypper pc_repo #{setting}") }
            end
          end

          it do
            is_expected.to contain_package('puppet-agent')
          end
        end
      end
    end
  end
end
