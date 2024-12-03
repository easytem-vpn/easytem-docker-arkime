sudo ip link set dev eth1 mtu 4500

sudo /usr/sbin/ip link set eth1 up || true
sudo /usr/sbin/ip link set eth1 promisc on || true
sudo /sbin/ethtool -G eth1 rx 4096 tx 4096 || true

sudo /sbin/ethtool -K eth1 rx off tx off sg off tso off ufo off gso off gro off lro off || true

sudo docker-compose up -d --build
