==============
Heat templates
==============

Repository of various Heat templates.

Usage
=====

- setup environment file, eg. ``env/salt_single_public.env``, look at example
  file first
- source credentials and required environment variables. You can download
  openrc file from Horizon dashboard.

  .. code-block:: bash

     source my_tenant-openrc.sh

- deploy stack

  .. code-block:: bash

     ./create_stack.sh salt_single_public

Stacks
======

.. list-table::
   :stub-columns: 1

   *  - openstack_cluster_public
      - Deploy OpenStack cluster with OpenContrail
   *  - salt_single_public
      - Base stack which deploys network and single-node Salt master
