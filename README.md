# Wireguard VPN

## Compatibility

| Platform | Version |
| -------- | ------- |
| debian   | 11      |

## Generate user configuration

```sh
bash /etc/wireguard/add-user.sh -n $CLIENT_NAME
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

This project is licensed under the [MIT](LICENSE.md).
