#!/usr/bin/perl

use Data::Printer;

use common::sense;

use lib::abs '../lib';

use C::GlobalSet;

my $set = C::GlobalSet->parse(\join('', <DATA>), 'kernel');

$set = $set->set;

p $set;

__DATA__

extern struct hlist_head unix_socket_table[2 * UNIX_HASH_SIZE];

static struct file_system_type parsec_fs_type =
{
	.name		= PARSECFS_NAME,
	.mount		= parsec_mount,
	.kill_sb	= kill_litter_super,
};


static struct super_operations parsec_sops = {
	.statfs = simple_statfs,
//	.destroy_inode = parsec_destroy_inode,
	.drop_inode = parsec_clear_inode
};

static struct file_operations parsec_ctl_ops = {
	.unlocked_ioctl	= parsec_ioctl,
	.compat_ioctl	= parsec_ioctl
};

static struct file_operations parsec_info_ops = {
	.read		= parsec_info_read,
	.write		= parsec_info_write,
};

static DEFINE_SPINLOCK(socket_update_slock);

extern  __typeof__(struct task_struct *) current_task;

extern  __typeof__(unsigned long) cpu_stop;

static int (*read_f[SYM_NUM]) (struct policydb *p, struct hashtab *h, void *fp) =
{
	common_read,
	class_read,
	role_read,
	type_read,
	user_read,
	cond_read_bool,
	sens_read,
	cat_read,
};


