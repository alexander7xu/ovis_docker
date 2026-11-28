FROM ubuntu:24.04
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
COPY entrypoint.bash /root/entrypoint.bash
ENTRYPOINT ["bash", "/root/entrypoint.bash"]
