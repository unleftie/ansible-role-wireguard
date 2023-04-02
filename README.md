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

## Local Testing

```sh
git clone https://github.com/unleftie/ansible-role-wireguard.git
cd ansible-role-wireguard/
molecule test
```

## Installation

> Upgradability notice: When upgrading from old version of this role, be aware that some files may be lost.

```yml
- name: Sample 1
  hosts: all
  become: true
  environment:
    PATH: "{{ ansible_env.PATH }}:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin"
  pre_tasks:
    - name: Ensure apt cache are updated
      apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_os_family == "Debian"
  tasks:
    - include_role:
        name: "ansible-role-wireguard"
```

## Adding new clients

```sh
bash /etc/wireguard/$WG_INTERFACE-files/add-client.sh
```

## 📝 License

This project is licensed under the [MIT](LICENSE).
