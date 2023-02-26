# Role for Wireguard setup

[![Ansible CI](https://github.com/unleftie/ansible-role-wireguard/actions/workflows/ansible-ci.yml/badge.svg)](https://github.com/unleftie/ansible-role-wireguard/actions/workflows/ansible-ci.yml)
[![Checkmarx KICS](https://github.com/unleftie/ansible-role-wireguard/actions/workflows/checkmarx-kics.yml/badge.svg)](https://github.com/unleftie/ansible-role-wireguard/actions/workflows/checkmarx-kics.yml)

## Compatibility

| Platform | Version |
| -------- | ------- |
| debian   | 11      |
| ubuntu   | 22.04   |

## Dependencies

- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) (v2.14+)
- [Molecule](https://molecule.readthedocs.io/en/latest/installation.html) (v4.0.4+) (for local testing)
- [Docker](https://docs.docker.com/get-docker/) (for local testing)

## Role dependencies

- iptables `required`
- iptables persistent `required`
- docker compose (see [prometheus_wireguard_exporter](https://github.com/MindFlavor/prometheus_wireguard_exporter)) `optional`
- prometheus (see [prometheus_wireguard_exporter](https://github.com/MindFlavor/prometheus_wireguard_exporter)) `optional`

## Testing

```sh
git clone https://github.com/unleftie/ansible-role-wireguard.git
cd ansible-role-wireguard/
molecule test
```

## Adding new clients

```sh
bash /etc/wireguard/$WG_INTERFACE-files/add-client.sh
```

## 📝 License

This project is licensed under the [MIT](LICENSE).
