# require 'pry'

node['mysql']['server']['packages'].each do |name|
  package name do
    action :install
  end
end

#----
node['mysql']['server']['directories'].each do |key, value|
  directory value do
    owner     'mysql'
    group     'mysql'
    mode      '0755'
    action    :create
    recursive true
  end
end

directory node['mysql']['data_dir'] do
  owner     'mysql'
  group     'mysql'
  action    :create
  recursive true
end

#----
template 'initial-my.cnf' do
  path '/etc/my.cnf'
  source 'my.cnf.erb'
  owner 'root'
  group 'root'
  mode '0644'
  notifies :run, 'execute[/usr/bin/mysql_install_db]', :immediately
  notifies :start, 'service[mysql-start]', :immediately
end

execute '/usr/bin/mysql_install_db' do
  action :nothing
  creates "#{node['mysql']['data_dir']}/mysql/user.frm"
end

# hax
service 'mysql-start' do
  service_name node['mysql']['server']['service_name']
  action :nothing
end


cmd = assign_root_password_cmd
execute 'assign-root-password' do
  command cmd
  action :run
  only_if "/usr/bin/mysql -u root -e 'show databases;'"
end

template '/etc/mysql_grants.sql' do
  source 'grants.sql.erb'
  owner  'root'
  group  'root'
  mode   '0600'
  action :create
  notifies :run, 'execute[install-grants]', :immediately
end

cmd = install_grants_cmd
execute 'install-grants' do
  command cmd
  action :nothing
  notifies :restart, 'service[mysql]', :immediately
end

#----
template 'final-my.cnf' do
  path '/etc/my.cnf'
  source 'my.cnf.erb'
  owner 'root'
  group 'root'
  mode '0644'
  notifies :reload, 'service[mysql]', :immediately
end

service 'mysql' do
  service_name node['mysql']['server']['service_name']
  supports     :status => true, :restart => true, :reload => true
  action       [:enable, :start]
end
