bash 'enable httpchk for haproxy' do
  code <<-'BASH'
    sed -i 's|^backend .*|\0\n  option httpchk GET /admin HTTP/1.1\\r\\nHost: localhost|' /etc/haproxy/haproxy.cfg
  BASH
  not_if 'grep httpchk /etc/haproxy/haproxy.cfg'
  notifies :reload, 'service[haproxy]', :delayed
end
