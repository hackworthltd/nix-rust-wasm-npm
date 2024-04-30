extern crate gol;
use criterion::{criterion_group, criterion_main, Criterion};

fn universe_ticks(c: &mut Criterion) {
    let mut universe = gol::Universe::new();

    c.bench_function("universe", |b| {
        b.iter(|| {
            universe.tick();
        })
    });
}

criterion_group!(benches, universe_ticks);
criterion_main!(benches);
