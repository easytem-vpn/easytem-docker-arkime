sudo ip link set dev tun0 mtu 4500

sudo /usr/sbin/ip link set tun0 up || true
sudo /usr/sbin/ip link set tun0 promisc on || true
sudo /sbin/ethtool -G tun0 rx 4096 tx 4096 || true

sudo /sbin/ethtool -K tun0 rx off tx off sg off tso off ufo off gso off gro off lro off || true

sudo docker-compose up -d --build
