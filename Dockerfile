FROM ubuntu:24.04
COPY entrypoint.bash /root/entrypoint.bash
ENTRYPOINT ["bash", "/root/entrypoint.bash"]
