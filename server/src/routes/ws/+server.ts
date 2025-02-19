import { type Peer, type Socket } from '@sveltejs/kit'

export const _peers = new Set<Peer>()

export const socket: Socket = {
  open(peer) {
    _peers.add(peer)
  },

  close(peer, _) {
    _peers.delete(peer)
  },

  error(peer, error) {
    console.error("Closing websocket peer due to error:", error)
    _peers.delete(peer)
  }
};
