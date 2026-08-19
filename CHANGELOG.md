# Changelog

## 1.1.8 — 2026-08-19

- Launcher regenerado com nxbootstrap 0.6.26: o validador do resultado do
  NXExtract passou a ser compativel com engines futuros (crise dos updates
  hibridos no muOS — launcher antigo + engine novo matava a instalacao com
  "unknown terminal result schema"). Sem mudanca de gameplay.
- Quem vem de versao anterior: faca instalacao LIMPA (apague a pasta
  angrybirds E o "Angry Birds Classic.sh" antes de extrair).

## 1.1.2-test.3

- Audio path revision exercised on ArkOS RK3326 / Mali-G31 with the exact
  release executable: native boot, ALSA output, first content transition and
  clean exit.
- Universal cursor kept from 1.1.1: right stick moves the pointer, `A` and `R3`
  tap, simultaneous `A`+`R3` still counts as a single touch, the pointer hides
  after two idle seconds and returns on movement.
- Left stick keeps driving the slingshot; D-pad and triggers keep their native
  actions.
- Public executable: ARMv7 hard-float, `GLIBC_2.17` ceiling, no RPATH/RUNPATH,
  no executable stack.

## 1.1.1

- Universal controller fix: polished pointer in menus and in gameplay, powers
  usable during a level, launcher no longer depends on the external `stat`.
- Star persistence confirmed physically (level 1 went from one to two stars).

## 1.1.0

- First universal PortMaster release of the ARMv7 port.
