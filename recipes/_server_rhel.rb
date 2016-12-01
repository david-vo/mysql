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
  notifies :run, 'bash[move mysql data to datadir]', :immediately
  notifies :restart, 'service[mysql-start]', :immediately
end

# The /usr/bin/mysql_install_db command initializes the MySQL data directory and creates the system if they don't
# exist. When the data directory is supposed to be moved, this command will attempt to initialize the data directory
# on the new location and will fail. This command is only required for the initial installation.
execute '/usr/bin/mysql_install_db' do
  action :nothing
  creates "#{node['mysql']['data_dir']}/mysql/user.frm"
  only_if { node['mysql']['data_dir'] == '/var/lib/mysql' }
end

bash 'move mysql data to datadir' do
  user 'root'
  code <<-EOH
  /sbin/service #{node['mysql']['server']['service_name']} stop &&
  mv /var/lib/mysql/* #{node['mysql']['data_dir']} &&
  rm -rf /var/lib/mysql &&
  ln -s #{node['mysql']['data_dir']} /var/lib/mysql &&
  #setup selinux policy if selinux is enforcing.
  if [ `getenforce` == "Enforcing" ];then
  semanage fcontext -a -t mysqld_db_t "#{node['mysql']['data_dir']}(/.*)?"
  restorecon -Rv #{node['mysql']['data_dir']}
  fi
  /sbin/service #{node['mysql']['server']['service_name']} start
  EOH
  action :nothing
  only_if "[ '/var/lib/mysql' != #{node['mysql']['data_dir']} ]"
  only_if "[ `stat -c %h #{node['mysql']['data_dir']}` -eq 2 ]"
  not_if '[ `stat -c %h /var/lib/mysql/` -eq 2 ]'
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
