# Wireguard VPN

## Compatibility

| Platform | Version |
| -------- | ------- |
| debian   | 11      |

## To generate user configuration

```sh
bash /etc/wireguard/add-user.sh -t $CLIENT_TAG
```

## Test Ansible role (Linux)

Required:
[Molecule](https://molecule.readthedocs.io/en/latest/installation.html),
[Vagrant](https://www.vagrantup.com/downloads),
[VirtualBox](https://www.virtualbox.org/wiki/Downloads)

```sh
git clone https://github.com/unleftie/ansible-role-wireguard.git
cd ansible-role-wireguard/
molecule test
```

## 📝 License

MIT
