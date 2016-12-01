#----
# Set up preseeding data for debian packages
#---
directory '/var/cache/local/preseeding' do
  owner 'root'
  group 'root'
  mode '0755'
  recursive true
end

template '/var/cache/local/preseeding/mysql-server.seed' do
  source 'mysql-server.seed.erb'
  owner 'root'
  group 'root'
  mode '0600'
  notifies :run, 'execute[preseed mysql-server]', :immediately
end

execute 'preseed mysql-server' do
  command '/usr/bin/debconf-set-selections /var/cache/local/preseeding/mysql-server.seed'
  action  :nothing
end

#----
# Install software
#----
# Do not install the 'mysql-server' package here as it should be installed after
# the my.cnf file is created. This is required in order to have the innodb log file
# created with the correct size set in my.cnf. The :install action of
# package[mysql-server] resource is notified by the template[/etc/mysql/my.cnf].
#
node['mysql']['server']['packages'].each do |name|
  package name do
    action name == 'mysql-server' ? :nothing : :install
  end
end

node['mysql']['server']['directories'].each do |key, value|
  directory value do
    owner     'mysql'
    group     'mysql'
    mode      '0775'
    action    :create
    recursive true
  end
end

template '/etc/mysql/my.cnf' do
  source 'my.cnf.erb'
  owner 'root'
  group 'root'
  mode '0644'
  notifies :install, 'package[mysql-server]', :immediately
  notifies :run, 'execute[/usr/bin/mysql_install_db]', :immediately
  notifies :run, 'bash[move mysql data to datadir]', :immediately
  notifies :restart, 'service[mysql]', :immediately
end

# The /usr/bin/mysql_install_db command initializes the MySQL data directory and creates the system if they don't
# exist. When the data directory is supposed to be moved, this command will attempt to initialize the data directory
# on the new location and will fail. This command is only required for the initial installation.
execute '/usr/bin/mysql_install_db' do
  action :nothing
  creates "#{node['mysql']['data_dir']}/mysql/user.frm"
  only_if { node['mysql']['data_dir'] == '/var/lib/mysql' }
end

# don't try this at home
# http://ubuntuforums.org/showthread.php?t=804126
bash 'move mysql data to datadir' do
  user 'root'
  code <<-EOH
  /usr/sbin/service mysql stop &&
  mv /var/lib/mysql/* #{node['mysql']['data_dir']} &&
  rm -rf /var/lib/mysql &&
  ln -s #{node['mysql']['data_dir']} /var/lib/mysql &&
  /usr/sbin/service mysql start
  EOH
  action :nothing
  only_if "[ '/var/lib/mysql' != #{node['mysql']['data_dir']} ]"
  only_if "[ `stat -c %h #{node['mysql']['data_dir']}` -eq 2 ]"
  not_if '[ `stat -c %h /var/lib/mysql/` -eq 2 ]'
end

cmd = assign_root_password_cmd
execute 'assign-root-password' do
  command cmd
  action :run
  only_if "/usr/bin/mysql -u root -e 'show databases;'"
end

#----
# Grants
#----
template '/etc/mysql_grants.sql' do
  source 'grants.sql.erb'
  owner  'root'
  group  'root'
  mode   '0600'
  notifies :run, 'execute[install-grants]', :immediately
end

cmd = install_grants_cmd
execute 'install-grants' do
  command cmd
  action :nothing
end

template '/etc/mysql/debian.cnf' do
  source 'debian.cnf.erb'
  owner 'root'
  group 'root'
  mode '0600'
  notifies :reload, 'service[mysql]'
end

#----
# data_dir
#----

# DRAGONS!
# Setting up data_dir will only work on initial node converge...
# Data will NOT be moved around the filesystem when you change data_dir
# To do that, we'll need to stash the data_dir of the last chef-client
# run somewhere and read it. Implementing that will come in "The Future"

directory node['mysql']['data_dir'] do
  owner     'mysql'
  group     'mysql'
  action    :create
  recursive true
end

template '/etc/init/mysql.conf' do
  source 'init-mysql.conf.erb'
  only_if { node['platform_family'] == 'ubuntu' }
end

template '/etc/apparmor.d/usr.sbin.mysqld' do
  source 'usr.sbin.mysqld.erb'
  action :create
  notifies :reload, 'service[apparmor-mysql]', :immediately
end

service 'apparmor-mysql' do
  service_name 'apparmor'
  action :nothing
  supports :reload => true
end


service 'mysql' do
  service_name 'mysql'
  supports     :status => true, :restart => true, :reload => true
  action       [:enable, :start]
  provider     Chef::Provider::Service::Upstart if node['platform'] == 'ubuntu'
end
