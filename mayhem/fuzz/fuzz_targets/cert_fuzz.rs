#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    if let Ok(value) = rasn::der::decode::<rasn_pkix::Certificate>(data) {
        assert_eq!(
            value,
            rasn::der::decode(&rasn::der::encode(&value).unwrap()).unwrap()
        );
    }
});
