-- Migration de exemplo em .sql: lida em runtime, nao exige recompilar o CLI.
alter table `users` add `phone` varchar(20) null after `name`;
