# Negentropy Swift

A swift implementation of the negentropy project found here: https://github.com/hoytech/negentropy

## Introduction

The Negentropy Swift library utilizes Negentropy's syncing method to efficiently sync any number of lmdb databases in an environment. For more information on the specifics of Negentropy's syncing methods, see the source project (https://github.com/hoytech/negentropy). This project takes the liberty of implementing the core Negentropy algorithms as an extension of the QuickLMDB library's databases. This way, the Negentropy functions are called directly by the database rather than taking creating a Negentropy class with a database variable.

In order to comply with swift concurrency, a single pthread and transaction are created per LMDB environment. Each of the syncing parties create their respective pthread: a sync pthread for the initiator's environment; a listener pthread for the responder's environment. The threads run for the lifetime of the sync operation on a single LMDB transaction per environment.

## Syncing
This library uses WireGuard Swift (https://github.com/tannerdsilva/wireguard-swift) as a data transfer layer for syncing two parties.
