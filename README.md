# Role for Wireguard VPN setup

## Compatibility

| Platform | Version |
| -------- | ------- |
| debian   | 11      |

## Dependencies

- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) (v2.12+)
- [Molecule](https://molecule.readthedocs.io/en/latest/installation.html) (for local testing)
- [Vagrant](https://www.vagrantup.com/downloads) (for local testing)
- [VirtualBox](https://www.virtualbox.org/wiki/Downloads) (for local testing)

## Role dependencies

- iptables `(required)`
- docker compose (see [prometheus_wireguard_exporter](https://github.com/MindFlavor/prometheus_wireguard_exporter))
- prometheus (see [prometheus_wireguard_exporter](https://github.com/MindFlavor/prometheus_wireguard_exporter))

## Testing

```sh
git clone https://github.com/unleftie/ansible-role-wireguard.git
cd ansible-role-wireguard/
molecule test
```

## Adding new clients

```sh
bash /etc/wireguard/$WG_INTERFACE-files/add-client.sh -n $CLIENT_NAME
```

## 📝 License

This project is licensed under the [MIT](LICENSE.md).
