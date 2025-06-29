docker build -t ubuntu_latest_snap .
docker run -dt --privileged --cap-add=SYS_CHROOT --name ubulatestsnap --hostname ubusnplocal ubuntu_latest_snap
